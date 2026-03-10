# Ecliptix iOS - Makefile
# Convenient commands for development workflow

.PHONY: help setup install-tools generate-protos validate-proto-contract clean build test xcode add-to-xcode

# Default target
help:
	@echo "Ecliptix iOS - Available Commands"
	@echo "=================================="
	@echo ""
	@echo "  make setup           - Full setup (tools + dependencies + generate)"
	@echo "  make install-tools   - Install protoc and gRPC tools"
	@echo "  make generate-protos - Generate Swift code from .proto files"
	@echo "  make validate-proto-contract - Compare iOS protos against server wire contract"
	@echo "  make clean           - Clean generated files and build artifacts"
	@echo "  make build           - Build Xcode project"
	@echo "  make test            - Run tests"
	@echo "  make xcode           - Open Xcode project"
	@echo "  make open-for-xcode  - Open Xcode + Finder + Instructions (START HERE)"
	@echo "  make add-to-xcode    - Guide for adding files to Xcode"
	@echo "  make pods-install    - Install CocoaPods dependencies"
	@echo "  make spm-resolve     - Resolve Swift Package Manager dependencies"
	@echo ""

# Full setup
setup: install-tools generate-protos
	@echo "✅ Setup complete!"

# Install required tools
install-tools:
	@echo "🔧 Installing proto tools..."
	@./Scripts/setup-proto-tools.sh

# Generate Swift code from proto files
generate-protos:
	@echo "⚙️  Generating Swift code from protos..."
	@./Scripts/generate-protos.sh

validate-proto-contract:
	@echo "🔎 Validating proto contract..."
	@./Scripts/validate-proto-contract.py

# Clean generated files
clean:
	@echo "🧹 Cleaning generated files..."
	@rm -rf Generated/
	@rm -rf DerivedData/
	@rm -rf .build/
	@echo "✅ Clean complete"

# Build Xcode project
build: generate-protos
	@echo "🏗  Building Xcode project..."
	@xcodebuild -project Ecliptix-iOS.xcodeproj -scheme Ecliptix-iOS -configuration Debug

# Run tests
test:
	@echo "🧪 Running tests..."
	@xcodebuild test -project Ecliptix-iOS.xcodeproj -scheme Ecliptix-iOS -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

# Install CocoaPods dependencies
pods-install:
	@echo "📦 Installing CocoaPods dependencies..."
	@pod install

# Resolve SPM dependencies
spm-resolve:
	@echo "📦 Resolving Swift Package Manager dependencies..."
	@xcodebuild -resolvePackageDependencies -project Ecliptix-iOS.xcodeproj

# Open Xcode project
xcode:
	@echo "🚀 Opening Xcode..."
	@open Ecliptix-iOS.xcodeproj

# Open everything needed to add files to Xcode
open-for-xcode:
	@./Scripts/open-all-for-xcode.sh

# Add files to Xcode (interactive guide)
add-to-xcode:
	@./Scripts/add-files-to-xcode.sh

# Development workflow
dev: clean generate-protos build
	@echo "✅ Development build complete!"
