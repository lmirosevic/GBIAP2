Pod::Spec.new do |s|
  s.name                  = 'GBIAP2'
  s.version               = '1.1.1'
  s.summary               = 'Goonbee\'s In-App Purchases, simplified. Second Edition.'
  s.homepage              = 'https://github.com/lmirosevic/GBIAP2'
  s.license               = { type: 'Apache License, Version 2.0', file: 'LICENSE' }
  s.author                = { 'Luka Mirosevic' => 'luka@goonbee.com' }
  s.source                = { git: 'https://github.com/lmirosevic/GBIAP2.git', tag: s.version.to_s }
  s.ios.deployment_target = '5.0'
  s.requires_arc          = true
  s.source_files          = 'GBIAP2/GBIAP2.h', 'GBIAP2/GBIAP2Manager.{h,m}', 'GBIAP2/GBIAP2DebuggingModule.{h,m}'
  s.public_header_files   = 'GBIAP2/GBIAP2.h', 'GBIAP2/GBIAP2Manager.h', 'GBIAP2/GBIAP2DebuggingModule.h'
end
