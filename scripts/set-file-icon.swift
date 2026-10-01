import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: SetFileIcon <icon.icns> <file>")
}
guard let image = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fail("Could not read installer icon.")
}
guard NSWorkspace.shared.setIcon(image, forFile: CommandLine.arguments[2], options: []) else {
    fail("Could not set installer icon.")
}
