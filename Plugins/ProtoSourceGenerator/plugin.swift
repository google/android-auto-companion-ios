import PackagePlugin
import Foundation

/// Swift Package Manager Plugin that generates Swift sources for corresponding proto files.
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

    guard let protoc = try? context.tool(named: "protoc") else {
      print("Cannot generate due to missing protoc binary.")
      return []
    }

    guard let swiftGen = try? context.tool(named: "protoc-gen-swift") else {
      print("Cannot generate due to missing protoc-gen-swift binary.")
      return []
    }

    guard let target = target as? SourceModuleTarget else {
      print("ProtoSourceGenerator bailing due to non source module target: \(target).")
      return []
    }

    return target.sourceFiles(withSuffix: "proto").map { proto in
      let input = proto.url
      print("Generating Swift Source for proto: \(input.path)")
      let protoName = input.deletingPathExtension().lastPathComponent
      let output = context.pluginWorkDirectoryURL.appendingPathComponent("\(protoName).pb.swift")
      let protoDir = input.deletingLastPathComponent()
      let arguments = [
        "--swift_opt=Visibility=Public",
        "--plugin=protoc-gen-swift=\(swiftGen.url.path)",
        "\(input.lastPathComponent)",
        "--swift_out=\(context.pluginWorkDirectoryURL.path)/.",
        "--proto_path=\(protoDir.path)"
      ]
      return .buildCommand(
        displayName: "Generating Swift for: \(input.path)",
        executable: protoc.url,
        arguments: arguments,
        inputFiles: [input],
        outputFiles: [output]
      )
    }
  }
}
