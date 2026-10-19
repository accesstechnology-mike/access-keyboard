# CI only: adds a hosted unit-test target that renders the real app screens in
# the Simulator so the workflow can capture them with `simctl io screenshot`.
# The project file is modified on the runner only, never committed.
require 'xcodeproj'
require 'rexml/document'

project_path = File.expand_path('../../AccessKeyboard.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |t| t.name == 'AccessKeyboard' } or abort 'no app target'

target = project.new_target(:unit_test_bundle, 'ReviewShots', :ios, '18.0')
group = project.main_group.new_group('ReviewShots', 'scripts/review_shots')
file = group.new_file('ReviewShotsTests.swift')
target.add_file_references([file])
target.add_dependency(app)
target.build_configurations.each do |config|
  s = config.build_settings
  s['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/AccessKeyboard.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/AccessKeyboard'
  s['BUNDLE_LOADER'] = '$(TEST_HOST)'
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['PRODUCT_NAME'] = 'ReviewShots'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'app.access.keyboard.reviewshots'
  s['SWIFT_VERSION'] = '5.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
  s['CODE_SIGNING_ALLOWED'] = 'NO'
end
target.product_reference.path = 'ReviewShots.xctest' if target.product_reference
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(target)
scheme.set_launch_target(app)
scheme.save_as(project_path, 'ReviewShots', true)

# xcodebuild test uses TestAction, not LaunchAction. The AccessKeyboard scheme
# only sets StoreKit on LaunchAction (fine for Run). Wire the same local
# catalogue onto both actions here so Product.products reads
# AccessKeyboard.storekit in CI instead of falling through to Sandbox.
# Same identifier string as AccessKeyboard.xcscheme.
scheme_path = File.join(project_path, 'xcshareddata/xcschemes/ReviewShots.xcscheme')
doc = REXML::Document.new(File.read(scheme_path))
storekit_xml = lambda {
  el = REXML::Element.new('StoreKitConfigurationFileReference')
  el.add_attribute('identifier', 'AccessKeyboard/AccessKeyboard.storekit')
  el
}
%w[TestAction LaunchAction].each do |action_name|
  action = doc.root.elements[action_name]
  next unless action
  action.elements.delete('StoreKitConfigurationFileReference') if action.elements['StoreKitConfigurationFileReference']
  action.add_element(storekit_xml.call)
end
formatter = REXML::Formatters::Pretty.new(3)
formatter.compact = true
File.open(scheme_path, 'w') { |f| formatter.write(doc, f); f.write("\n") }
puts 'ReviewShots target and scheme added (StoreKit config on TestAction + LaunchAction)'
