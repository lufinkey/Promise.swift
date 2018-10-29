Pod::Spec.new do |s|
  s.name         = "Promise"
  s.version      = "1.0.0"
  s.summary      = "Simple Promise class written in swift"
  s.homepage     = "https://github.com/lufinkey/Promise.swift"
  s.license      = { :type => "MIT" }
  s.author             = { "Luis Finke" => "luisfinke@gmail.com" }
  s.social_media_url   = "http://twitter.com/lufinkey"
  s.platform     = :ios
  s.ios.deployment_target = '8.0'
  s.source       = { :git => "https://github.com/lufinkey/Promise.swift.git", :tag => s.version }
  s.source_files  = "Promise/*.{swift}"
  s.swift_version = '4.2'
  s.requires_arc = true
end
