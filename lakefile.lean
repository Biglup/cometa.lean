/-
Copyright 2026 Biglup Labs
SPDX-License-Identifier: Apache-2.0

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-/

import Lake

open System Lake DSL

-- PACKAGE --------------------------------------------------------------------

package cometa where
  version := v!"0.1.0"
  description := "Native Cardano transaction construction and inspection for Lean"
  license := "Apache-2.0"
  moreLeanArgs := #["-DwarningAsError=true", "-Dlinter.missingDocs=true"]

-- NATIVE LIBRARY --------------------------------------------------------------

input_file nativeSetup where
  path := "scripts" / "setup-native.py"
  text := true

/-- Prepare the pinned native dependency on demand, including downstream builds. -/
target nativeLibraryFile pkg : FilePath := do
  let setup ← nativeSetup.fetch
  setup.mapM fun setupFile => do
    proc { cmd := "python3", args := #[setupFile.toString, "--ensure"] }
    let directory := pkg.dir / ".lake" / "native"
    let library := directory / "lib" / nameToSharedLib "cardano-c"
    addTrace (← computeTrace library)
    addTrace (← computeTrace (TextFilePath.mk (directory / "install.json")))
    return library

input_file bridgeSource where
  path := "cbits" / "cometa_lean.c"
  text := true

input_file componentSource where
  path := "cbits" / "cometa_components.h"
  text := true

input_file transactionBuildSource where
  path := "cbits" / "cometa_transaction_build.h"
  text := true

input_file withdrawalsSource where
  path := "cbits" / "cometa_withdrawals.h"
  text := true

target nativeLibrary _pkg : Dynlib := do
  let file ← nativeLibraryFile.fetch
  file.mapM fun path => do
    return { name := "cardano-c", path := path }

target bridgeObject pkg : FilePath := do
  let source ← bridgeSource.fetch
  let components ← componentSource.fetch
  let withdrawals ← withdrawalsSource.fetch
  let transactionBuild ← transactionBuildSource.fetch
  let native ← nativeLibraryFile.fetch
  let flags := #["-I", (← getLeanIncludeDir).toString,
    "-I", (pkg.dir / ".lake" / "native" / "include").toString]
  buildO (pkg.buildDir / "c" / "cometa_lean.o") source flags
    #["-fPIC", "-std=c11", "-Wall", "-Wextra", "-Werror"] "cc" do
      let _ ← components.await
      addTrace components.getTrace
      let _ ← withdrawals.await
      addTrace withdrawals.getTrace
      let _ ← transactionBuild.await
      addTrace transactionBuild.getTrace
      addTrace (← getLeanTrace)
      let _ ← native.await
      addTrace native.getTrace
      return (← getTrace)

target bridgeLibrary pkg : Dynlib := do
  let object ← bridgeObject.fetch
  let native ← nativeLibrary.fetch
  let nativeDir := (← IO.FS.realPath pkg.dir) / ".lake" / "native" / "lib"
  let library ← buildLeanSharedLib "cometa_lean" (pkg.sharedLibDir / nameToSharedLib "cometa_lean")
    #[object] #[native] #[] #[s!"-Wl,-rpath,{nativeDir}"]
    (linkDeps := true)
  -- The bridge links cardano-c itself. Consumers need that library at runtime,
  -- not as a direct link input against Lean's older Linux glibc sysroot.
  library.mapM fun result =>
    pure { result with deps := #[], runtimeOnlyDeps := result.deps }

-- LEAN TARGETS ---------------------------------------------------------------

@[default_target]
lean_lib Cometa where
  moreLinkLibs := #[bridgeLibrary]
  precompileModules := true

lean_lib TestSupport where
  roots := #[`Tests.Transaction, `Tests.TransactionFixtures, `Tests.Output, `Tests.OutputFixtures,
    `Tests.Decoding, `Tests.Assembly, `Tests.Withdrawals]

@[test_driver]
lean_exe cometaTests where
  root := `Tests.Main

lean_exe inspectAddress where
  root := `Examples.InspectAddress

lean_exe inspectTransaction where
  root := `Examples.InspectTransaction

lean_exe buildOutput where
  root := `Examples.BuildOutput

lean_exe buildTransaction where
  root := `Examples.BuildTransaction

lean_exe withdrawRewards where
  root := `Examples.WithdrawRewards
