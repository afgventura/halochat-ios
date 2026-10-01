Pod::Spec.new do |s|
  s.name         = "HaloChat"
  s.version      = "0.1.0"
  s.summary      = "HaloAI in-app customer chat SDK: conversation, history, send, realtime, push."
  s.homepage     = "https://www.haloai.co.id"
  s.license      = { :type => "Proprietary" }
  s.author       = { "HaloAI" => "engineering@haloai.co.id" }
  s.source       = { :git => "https://github.com/afgventura/halochat-ios.git", :tag => s.version.to_s }
  s.ios.deployment_target = "15.0"
  s.swift_version = "5.9"
  s.source_files = "Sources/HaloChat/**/*.swift"
end
