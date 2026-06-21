# CI(クラウドのMac)上で、PencilKitプラグインのファイルを
# 自動生成された Xcode プロジェクトに登録するスクリプト。
# 使い方: gem install xcodeproj && ruby scripts/add_plugin_files.rb
require 'xcodeproj'

project_path = 'ios/App/App.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'App' }
raise 'App target not found' unless target

group = project.main_group.find_subpath('App', false)
raise 'App group not found' unless group

['PencilKitPlugin.swift'].each do |filename|
  next if group.files.any? { |f| f.path == filename }
  ref = group.new_reference(filename)
  target.add_file_references([ref])
  puts "added #{filename}"
end

project.save
puts 'Xcode project updated.'
