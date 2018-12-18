# Copyright (C) 2018 The Bazel Common Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Skylark rules for jarjar. See https://github.com/pantsbuild/jarjar
"""

def _jarjar_library(ctx):
    _rules_file = ctx.actions.declare_file('jarjar.rules')
    ctx.actions.write(
        output = _rules_file,
        content = "\n".join(ctx.attr.rules),
    )

    jar_files = depset(transitive = [jar.files for jar in ctx.attr.jars]).to_list()

    command = """
  JAVA_HOME=$(pwd)/{java_home} # this is used outside of the root

  TMPDIR=$(mktemp -d)
  for jar in {jars}; do
    unzip -qq -B $jar -d $TMPDIR
  done

  pushd $TMPDIR &>/dev/null

  # Concatenate similar files in META-INF/services
  for file in META-INF/services/*; do
    original=$(echo $file | sed s/"~[0-9]*$"//)
    if [[ "$file" != "$original" ]]; then
      cat $file >> $original
      rm $file
    fi
  done

  rm META-INF/MANIFEST.MF*
  rm -rf META-INF/maven/
  duplicate_files=$(find * -type f -regex ".*~[0-9]*$")
  if [[ -n "$duplicate_files" ]]; then
    echo "Error: duplicate files in merged jar: $duplicate_files"
    exit 1
  fi
  $JAVA_HOME/bin/jar cf combined.jar *

  popd &>/dev/null

  {jarjar} process {rules_file} $TMPDIR/combined.jar {outfile}
  rm -rf $TMPDIR
  """.format(
        jars = " ".join([jar.path for jar in jar_files]),
        java_home = str(ctx.attr._jdk[java_common.JavaRuntimeInfo].java_home),
        jarjar = ctx.executable._jarjar.path,
        rules_file = _rules_file.path,
        outfile = ctx.outputs.jar.path,
    )

    ctx.actions.run_shell(
        command = command,
        inputs = [
            ctx.executable._jarjar,
            _rules_file,
        ] + jar_files + ctx.files._jdk,
        outputs = [ctx.outputs.jar],
    )

    return [JavaInfo(
        output_jar=ctx.outputs.jar,
        compile_jar=ctx.outputs.jar,
        deps=[x[JavaInfo] for x in ctx.attr.deps])]

jarjar_library = rule(
    attrs = {
        "rules": attr.string_list(),
        "jars": attr.label_list(
            allow_files = [".jar"],
        ),
        "deps": attr.label_list(
            providers = [JavaInfo]
        ),
        "_jarjar": attr.label(
            default = Label("//tools/jarjar"),
            executable = True,
            cfg = "host",
        ),
        "_jdk": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
            providers = [java_common.JavaRuntimeInfo],
        ),
    },
    outputs = {
        "jar": "%{name}.jar",
    },
    implementation = _jarjar_library,
)
