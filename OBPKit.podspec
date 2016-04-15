Pod::Spec.new do |s|
  s.name = "OBPKit"
  s.version = "1.0.0"
  s.summary = "Ease access to servers offering the Open Bank Project API."
  s.description = "OBPKit is quick to integrate into your iOS app or OSX application, and makes authorisation of sessions and marshalling of resources through the Open Bank Project API simple and easy."
  s.homepage = "https://github.com/OpenBankProject/OBPKit-iOSX"
  s.license = "MIT"
  s.authors = {
    "Torsten Louland" => "torsten.louland@satisfyingstructures.com"
  }
  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.9"
  s.source = { :git => "https://github.com/OpenBankProject/OBPKit-iOSX.git", :tag => s.version }
  s.source_files  = "OBPKit/**/*.{h,m}", "Framework", "GenerateKey"
  s.public_header_files = "OBPKit/**/*.h", "Framework/*.h"
  s.preserve_paths = "Config/*.xcconfig"
  s.requires_arc = true
  s.dependency "STHTTPRequest", "~> 1.1.0"
  s.dependency "OAuthCore", "~> 0.0.1"
  s.dependency "UICKeyChainStore", "~> 2.1.0"
end
