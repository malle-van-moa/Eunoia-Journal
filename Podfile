# Uncomment the next line to define a global platform for your project
platform :ios, '17.0'

# Prevent framework embedding issues
install! 'cocoapods',
         :disable_input_output_paths => true,
         :preserve_pod_file_structure => true

target 'Eunoia-Journal' do
  use_frameworks!
  
  # Google Sign In and dependencies
  pod 'GoogleSignIn', '7.0.0'
  
  target 'Eunoia-JournalTests' do
    inherit! :search_paths
  end

  target 'Eunoia-JournalUITests' do
    inherit! :search_paths
  end
  
  # Script phase to handle framework installation using wrapper script
  script_phase :name => 'Copy Frameworks',
               :script => '/bin/bash "${SRCROOT}/scripts/copy_frameworks.sh"',
               :execution_position => :after_compile,
               :input_files => [],
               :output_files => [],
               :show_env_vars_in_log => true
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Basic settings
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      
      # Module settings
      config.build_settings['DEFINES_MODULE'] = 'YES'
      config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
      config.build_settings['SWIFT_VERSION'] = '5.0'
      
      # Framework settings
      if target.respond_to?(:product_type) && target.product_type == "com.apple.product-type.framework"
        config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
        config.build_settings['SKIP_INSTALL'] = 'YES'
        config.build_settings['DYLIB_INSTALL_NAME_BASE'] = '@rpath'
        config.build_settings['INSTALL_PATH'] = '@executable_path/Frameworks'
        config.build_settings['FRAMEWORK_VERSION'] = 'A'
        
        # Framework script settings
        config.build_settings['FRAMEWORK_SEARCH_PATHS'] = ['$(inherited)', '${PODS_ROOT}/**', '${PODS_XCFRAMEWORKS_BUILD_DIR}/**']
        config.build_settings['HEADER_SEARCH_PATHS'] = ['$(inherited)', '${PODS_ROOT}/**']
        
        # Prevent framework code signing issues
        config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
        config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
        config.build_settings['CODE_SIGN_IDENTITY'] = ''
      end
      
      # Disable script sandboxing for all targets
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      config.build_settings['SHELL_SCRIPT_SANDBOXING'] = 'NO'
    end
  end

  # Main target configuration
  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.user_project.native_targets.each do |native_target|
      native_target.build_configurations.each do |config|
        if native_target.name == 'Eunoia-Journal'
          # Info.plist settings
          config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
          config.build_settings['INFOPLIST_FILE'] = 'Eunoia-Journal/Info.plist'
          config.build_settings['MARKETING_VERSION'] = '1.0'
          config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
          
          # Framework settings
          config.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = '$(inherited)'
          config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
            '$(inherited)',
            '@executable_path/Frameworks'
          ]
          
          # Linking flags
          config.build_settings['OTHER_LDFLAGS'] = '$(inherited) -ObjC'
          
          # Framework search paths
          config.build_settings['FRAMEWORK_SEARCH_PATHS'] = [
            '$(inherited)',
            '${PODS_ROOT}/**',
            '${PODS_XCFRAMEWORKS_BUILD_DIR}/**'
          ]
          
          # Fix code signing
          config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Development'
          config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
          
          # Script settings
          config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
          config.build_settings['SHELL_SCRIPT_SANDBOXING'] = 'NO'
        end
      end
    end
  end
  
  # Fix Pods project build settings
  installer.pods_project.build_configurations.each do |config|
    config.build_settings.delete('CODE_SIGNING_ALLOWED')
    config.build_settings.delete('CODE_SIGNING_REQUIRED')
    config.build_settings.delete('CODE_SIGN_IDENTITY')
    config.build_settings['EXPANDED_CODE_SIGN_IDENTITY'] = ''
    config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
    config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    config.build_settings['SHELL_SCRIPT_SANDBOXING'] = 'NO'
  end
end
