#!/usr/bin/env ruby

# Ecliptix iOS - Xcode Project Setup Script
# Automatically adds proto files, scripts, and build phases to Xcode project

require 'xcodeproj'

# Colors for output
class String
  def red; "\e[31m#{self}\e[0m"; end
  def green; "\e[32m#{self}\e[0m"; end
  def yellow; "\e[33m#{self}\e[0m"; end
  def blue; "\e[34m#{self}\e[0m"; end
end

puts "🔧 Ecliptix iOS - Xcode Project Setup".blue
puts "======================================\n".blue

# Paths
script_dir = File.dirname(__FILE__)
project_root = File.expand_path('..', script_dir)
xcodeproj_path = File.join(project_root, 'Ecliptix-iOS.xcodeproj')

# Check if xcodeproj gem is installed
begin
  require 'xcodeproj'
rescue LoadError
  puts "❌ xcodeproj gem not installed".red
  puts "Install with: gem install xcodeproj".yellow
  exit 1
end

# Open project
puts "📂 Opening Xcode project...".blue
project = Xcodeproj::Project.open(xcodeproj_path)
target = project.targets.first

# Get main group
main_group = project.main_group

# Add Protos folder as folder reference
puts "\n📦 Adding Protos folder...".blue
protos_ref = main_group.find_subpath('Protos', true) ||
             main_group.new_reference(File.join(project_root, 'Protos'))
protos_ref.last_known_file_type = 'folder'
protos_ref.source_tree = 'SOURCE_ROOT'
protos_ref.path = 'Protos'
puts "   ✓ Protos folder added as folder reference".green

# Add Scripts folder
puts "\n📜 Adding Scripts folder...".blue
scripts_group = main_group.find_subpath('Scripts') || main_group.new_group('Scripts')
scripts_path = File.join(project_root, 'Scripts')

Dir.glob(File.join(scripts_path, '*')).each do |script_file|
  next unless File.file?(script_file)
  filename = File.basename(script_file)

  # Check if file already exists
  unless scripts_group.files.find { |f| f.path == filename }
    file_ref = scripts_group.new_reference(filename)
    file_ref.source_tree = '<group>'
    puts "   ✓ Added #{filename}".green
  end
end

# Add root configuration files
puts "\n⚙️  Adding configuration files...".blue
config_files = ['Package.swift', 'Podfile', 'Makefile', '.gitignore']

config_files.each do |filename|
  file_path = File.join(project_root, filename)
  next unless File.exist?(file_path)

  # Check if file already exists in project
  unless main_group.find_file_by_path(filename)
    file_ref = main_group.new_reference(filename)
    file_ref.source_tree = 'SOURCE_ROOT'
    file_ref.path = filename
    puts "   ✓ Added #{filename}".green
  end
end

# Add documentation files
puts "\n📚 Adding documentation files...".blue
doc_files = [
  'README.md',
  'QUICKSTART.md',
  'PROTOS_README.md',
  'XCODE_SETUP.md',
  'PORTING_CHECKLIST.md',
  'MIGRATION_SUMMARY.md'
]

docs_group = main_group.find_subpath('Documentation') || main_group.new_group('Documentation')

doc_files.each do |filename|
  file_path = File.join(project_root, filename)
  next unless File.exist?(file_path)

  unless docs_group.find_file_by_path(filename)
    file_ref = docs_group.new_reference(filename)
    file_ref.source_tree = 'SOURCE_ROOT'
    file_ref.path = filename
    puts "   ✓ Added #{filename}".green
  end
end

# Add Run Script Build Phase for proto generation
puts "\n🔨 Adding proto generation build phase...".blue

proto_script_phase = target.shell_script_build_phases.find do |phase|
  phase.name == 'Generate Proto Files'
end

unless proto_script_phase
  proto_script_phase = target.new_shell_script_build_phase('Generate Proto Files')
  proto_script_phase.shell_script = <<~SCRIPT
    cd "$PROJECT_DIR"

    # Export PATH for Homebrew tools
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

    # Run proto generation
    if [ -f "./Scripts/generate-protos.sh" ]; then
        echo "🔧 Generating proto files..."
        ./Scripts/generate-protos.sh
    else
        echo "error: generate-protos.sh not found"
        exit 1
    fi
  SCRIPT

  # Move script phase before compile sources
  target.build_phases.move(proto_script_phase, 0)

  puts "   ✓ Proto generation build phase added".green
else
  puts "   ⚠️  Proto generation build phase already exists".yellow
end

# Add Generated folder as folder reference
puts "\n📁 Adding Generated folder reference...".blue
generated_ref = main_group.find_subpath('Generated', true) ||
                main_group.new_reference(File.join(project_root, 'Generated'))
generated_ref.last_known_file_type = 'folder'
generated_ref.source_tree = 'SOURCE_ROOT'
generated_ref.path = 'Generated'
puts "   ✓ Generated folder added".green

# Save project
puts "\n💾 Saving Xcode project...".blue
project.save
puts "   ✓ Project saved successfully".green

puts "\n✅ Xcode project setup complete!".green
puts "\n📝 Next steps:".blue
puts "   1. Open Ecliptix-iOS.xcodeproj in Xcode"
puts "   2. Run: make generate-protos"
puts "   3. Build project (⌘B)"
puts ""
