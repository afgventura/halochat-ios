Pod::Spec.new do |s|
  s.name         = "HaloChat"
  s.version      = "0.2.0"
  s.summary      = "HaloAI in-app customer chat SDK: core client plus an optional drop-in chat screen."
  s.homepage     = "https://www.haloai.co.id"
  s.license      = { :type => "Apache-2.0", :file => "LICENSE" }
  s.author       = { "HaloAI" => "engineering@haloai.co.id" }
  s.source       = { :git => "https://github.com/afgventura/halochat-ios.git", :tag => s.version.to_s }
  s.ios.deployment_target = "15.0"
  s.swift_version = "5.9"

  # `pod 'HaloChat'` stays core-only, exactly as in 0.1.x.
  s.default_subspecs = "Core"

  s.subspec "Core" do |core|
    core.source_files = "Sources/HaloChat/**/*.swift"
  end

  # `pod 'HaloChat/UI'`: the drop-in chat screen. With CocoaPods every subspec compiles into
  # the single `HaloChat` module, so apps `import HaloChat` (SwiftPM apps `import HaloChatUI`).
  s.subspec "UI" do |ui|
    ui.dependency "HaloChat/Core"
    ui.source_files = "Sources/HaloChatUI/**/*.swift"
    ui.resource_bundles = { "HaloChatUI" => ["Sources/HaloChatUI/Resources/*.lproj/*.strings"] }
    ui.frameworks = "UIKit", "SwiftUI", "PhotosUI", "QuickLook", "UniformTypeIdentifiers", "ImageIO"
  end
end
