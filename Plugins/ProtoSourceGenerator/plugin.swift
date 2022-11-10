import PackagePlugin
import Foundation

/// Swift Package Manager Plugin that generates Swift sources for corresponding proto files.
///
/// The `protoc` and `protoc-gen-swift` executables must be installed at `/usr/local/bin`. These
/// tools may be installed through https://github.com/Homebrew/brew.
///
/// The Swift sources will be output to the plugin's working directory. The generated types will
/// have `public` access and belong to a module whose name matches the target containing the proto
/// files. For example, if the plugin is applied to `AndroidAutoCompanionProtos` then a Swift file
/// will be generated for each proto in `AndroidAutoCompanionProtos`, each type in the file will
/// have public access, and they will belong to a module named `AndroidAutoCompanionProtos`.
@main struct ProtoSourceGenerator: BuildToolPlugin {
  func createBuildCommands(
    context: PackagePlugin.PluginContext,
    target: PackagePlugin.Target
  ) async throws -> [PackagePlugin.Command] {
    print("ProtoSourceGenerator generating Swift source files for the proto files.")

    guard let target = target as? SourceModuleTarget else {
      print("ProtoSourceGenerator bailing due to non source module target: \(target).")
      return []
    }

    return target.sourceFiles(withSuffix: "proto").map { proto in
      let input = proto.path
      print("Generating Swift Source for proto: \(input)")
      let output = context.pluginWorkDirectory.appending(["\(input.stem).pb.swift"])
      let executable = Path("/usr/local/bin/protoc")
      let protoDir = input.removingLastComponent()
      let arguments = [
        "--swift_opt=Visibility=Public",
        "--plugin=protoc-gen-swift=/usr/local/bin/protoc-gen-swift",
        "\(input.lastComponent)",
        "--swift_out=\(context.pluginWorkDirectory)/.",
        "--proto_path=\(protoDir)"
      ]
      return .buildCommand(
        displayName: "Generating Swift for: \(input)",
        executable: executable,
        arguments: arguments,
        inputFiles: [input],
        outputFiles: [output]
      )
    }
  }
}
