// Copyright 2015 Google Inc. All rights reserved.
// Copyright (C) 2018 The LineageOS Project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package generator

import (
	"fmt"
	"strings"

	"github.com/google/blueprint"
	"github.com/google/blueprint/proptools"

	"android/soong/android"
	"path/filepath"
)

func init() {
	android.RegisterModuleType("voltage_generator", GeneratorFactory)

	pctx.HostBinToolVariable("sboxCmd", "sbox")
}

var String = proptools.String

var (
	pctx = android.NewPackageContext("android/soong/generator")
)

type HostToolProvider interface {
	HostToolPath() android.OptionalPath
}

type hostToolDependencyTag struct {
	blueprint.BaseDependencyTag
}

var hostToolDepTag hostToolDependencyTag

type generatorProperties struct {
	// The command to run on one or more input files. Cmd supports substitution of a few variables
	// (the actual substitution is implemented in GenerateAndroidBuildActions below)
	//
	// Available variables for substitution:
	//
	//  $(location): the path to the first entry in tools or tool_files
	//  $(location <label>): the path to the tool or tool_file with name <label>
	//  $(genDir): the sandbox directory for this tool; contains $(out)
	//  $$: a literal $
	//
	Cmd *string

	// name of the modules (if any) that produces the host executable.   Leave empty for
	// prebuilts or scripts that do not need a module to build them.
	Tools []string

	// Local file that is used as the tool
	Tool_files []string

	// List of directories to export as headers
	Export_include_dirs []string

	// List of directories to export as sources
	Export_source_dirs []string

	// Root directory for dep_files.
	// Relative to top build dir.
	Dep_root *string

	// Declare list of files that should be used for timestamp dependency checking
	Dep_files []string
}

type Module struct {
	android.ModuleBase

	properties generatorProperties

	rule blueprint.Rule

	// Tool dependencies
	implicitDeps android.Paths
	// Deps from input files declared in dep_files property.
	inputDeps android.Paths

	exportedIncludeDirs android.Paths
	exportedSourceDirs  android.Paths

	outputDeps android.Paths
}

// These three methods satisfy genrule.SourceFileGenerator.
// Which cc modules check for when including headers etc.
func (g *Module) GeneratedHeaderDirs() android.Paths {
	return g.exportedIncludeDirs
}

func (g *Module) GeneratedSourceFiles() android.Paths {
	return g.exportedSourceDirs
}

func (g *Module) GeneratedDeps() android.Paths {
	return g.outputDeps
}

func (g *Module) DepsMutator(ctx android.BottomUpMutatorContext) {
	android.ExtractSourcesDeps(ctx, g.properties.Dep_files)
	android.ExtractSourcesDeps(ctx, g.properties.Tool_files)
	if g, ok := ctx.Module().(*Module); ok {
		if len(g.properties.Tools) > 0 {
			ctx.AddFarVariationDependencies(ctx.Config().BuildOSTarget.Variations(),
				hostToolDepTag, g.properties.Tools...)
		}
	}
}

func (g *Module) GenerateAndroidBuildActions(ctx android.ModuleContext) {
	if len(g.properties.Export_include_dirs) > 0 {
		for _, dir := range g.properties.Export_include_dirs {
			g.exportedIncludeDirs = append(g.exportedIncludeDirs,
				android.PathForModuleGen(ctx, dir))
		}
	} else {
		g.exportedIncludeDirs = append(g.exportedIncludeDirs, android.PathForModuleGen(ctx, ""))
	}
	if len(g.properties.Export_source_dirs) > 0 {
		for _, dir := range g.properties.Export_source_dirs {
			g.exportedSourceDirs = append(g.exportedSourceDirs,
				android.PathForModuleGen(ctx, dir))
		}
	} else {
		g.exportedSourceDirs = append(g.exportedSourceDirs, android.PathForModuleGen(ctx, ""))
	}

	tools := map[string]android.Path{}

	if len(g.properties.Tools) > 0 {
		ctx.VisitDirectDepsProxyAllowDisabled(func(proxy android.ModuleProxy) {
			module := android.PrebuiltGetPreferred(ctx, proxy)
			switch ctx.OtherModuleDependencyTag(module) {
			case hostToolDepTag:
				tool := ctx.OtherModuleName(module)
				var path android.OptionalPath

				if t, ok := module.(HostToolProvider); ok {
					if !t.(android.Module).Enabled(ctx) {
						if ctx.Config().AllowMissingDependencies() {
							ctx.AddMissingDependencies([]string{tool})
						} else {
							ctx.ModuleErrorf("depends on disabled module %q", tool)
						}
						break
					}
					path = t.HostToolPath()
				} else {
					ctx.ModuleErrorf("%q is not a host tool provider", tool)
					break
				}

				if path.Valid() {
					g.implicitDeps = append(g.implicitDeps, path.Path())
					if _, exists := tools[tool]; !exists {
						tools[tool] = path.Path()
					} else {
						ctx.ModuleErrorf("multiple tools for %q, %q and %q", tool, tools[tool], path.Path().String())
					}
				} else {
					ctx.ModuleErrorf("host tool %q missing output file", tool)
				}
			default:
				ctx.ModuleErrorf("unknown dependency on %q", ctx.OtherModuleName(module))
			}
		})
	}

	if ctx.Failed() {
		return
	}

	toolFiles := ctx.ExpandSources(g.properties.Tool_files, nil)
	for _, tool := range toolFiles {
		g.implicitDeps = append(g.implicitDeps, tool)
		if _, exists := tools[tool.Rel()]; !exists {
			tools[tool.Rel()] = tool
		} else {
			ctx.ModuleErrorf("multiple tools for %q, %q and %q", tool, tools[tool.Rel()], tool.Rel())
		}
	}

	// Determine root dir for dep_files.  Defaults to current ctx ModuleDir.
	depRoot := String(g.properties.Dep_root)
	if depRoot == "" {
		depRoot = ctx.ModuleDir()
	} else {
		depRoot = voltageExpandVariables(ctx, depRoot)
	}

	// Glob dep_files property
	for _, dep_file := range g.properties.Dep_files {
		dep_file = voltageExpandVariables(ctx, dep_file)
		globPath := filepath.Join(depRoot, dep_file)
		paths, err := ctx.GlobWithDeps(globPath, nil)
		if err != nil {
			ctx.ModuleErrorf("unable to glob %s: %s", globPath, err.Error())
			return
		}
		for _, path := range paths {
			g.inputDeps = append(g.inputDeps, android.PathForSourceRelaxed(ctx, path))
		}
	}

	exCmd := voltageExpandVariables(ctx, String(g.properties.Cmd))

	// Dummy output dep
	dummyDep := android.PathForModuleGen(ctx, ".dummy_dep")

	genDir := android.PathForModuleGen(ctx)

	// Pick a unique rule name and the user-visible description.
	manifestName := "vos.sbox.textproto"
	desc := "generate"
        name := "generator"
	manifestPath := android.PathForModuleOut(ctx, manifestName)

	// Use a RuleBuilder to create a rule that runs the command inside an sbox sandbox.
	rule := android.NewRuleBuilder(pctx, ctx).Sbox(genDir, manifestPath).SandboxTools()
	rule.Command().Text("touch").Output(dummyDep)
        cmd := rule.Command()

	rawCommand, err := android.Expand(exCmd, func(name string) (string, error) {
		switch name {
		case "location":
			if len(g.properties.Tools) == 0 && len(toolFiles) == 0 {
				return "", fmt.Errorf("at least one `tools` or `tool_files` is required if $(location) is used")
			}

			if len(g.properties.Tools) > 0 {
				return tools[g.properties.Tools[0]].String(), nil
			} else {
				return tools[toolFiles[0].Rel()].String(), nil
			}
		case "genDir":
			return android.PathForModuleGen(ctx).String(), nil
		default:
			if strings.HasPrefix(name, "location ") {
				label := strings.TrimSpace(strings.TrimPrefix(name, "location "))
				if tool, ok := tools[label]; ok {
					return tool.String(), nil
				} else {
					return "", fmt.Errorf("unknown location label %q", label)
				}
			}
			return "", fmt.Errorf("unknown variable '$(%s)'", name)
		}
	})

	if err != nil {
		ctx.PropertyErrorf("cmd", "%s", err.Error())
		return
	}

	cmd.Text(rawCommand)
	cmd.ImplicitOutput(dummyDep)
	cmd.Implicits(g.inputDeps)
	cmd.Implicits(g.implicitDeps)

	g.outputDeps = append(g.outputDeps, dummyDep)

	rule.Build(name, desc)
}

func NewGenerator() *Module {
	module := &Module{}
	module.AddProperties(&module.properties)
	return module
}

func GeneratorFactory() android.Module {
	m := NewGenerator()
	android.InitAndroidModule(m)
	return m
}
