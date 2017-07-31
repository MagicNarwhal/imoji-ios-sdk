Pod::Spec.new do |s|

  s.name     = 'ImojiSDK-MagicNarwhal'
  s.version  = '2.3.5'
  s.license  = 'MIT'
  s.summary  = 'iOS SDK for Imoji. Integrate Stickers and custom emojis into your applications easily!'
  s.homepage = 'http://imoji.io/developers'
  s.authors = {'Nima Khoshini'=>'nima@imojiapp.com', 'Alex Hoang'=>'alex@imojiapp.com'}
  s.libraries = 'z'

  s.source   = { :git => 'https://github.com/MagicNarwhal/imoji-ios-sdk.git', :tag => s.version.to_s }
  s.ios.deployment_target = '7.0'

  s.requires_arc = true

  s.subspec 'Core' do |ss|
    ss.dependency "Bolts/Tasks", '~> 1.2'
    ss.dependency "YYImage-MagicNarwhal/WebP", '~>1.0'

    ss.ios.source_files = 'Source/Core/**/*.{h,m}'
    ss.ios.public_header_files = 'Source/Core/*.h', 'Source/Core/Util/YYImage/*.h'
  end
  
end
