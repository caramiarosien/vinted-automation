#!/usr/bin/env python3
"""Regenerate a dependency-free Xcode project using the local core package."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def quoted(text): return '"' + text.replace('\\', '\\\\').replace('"','\\"') + '"'
objects = []
def add(name, text): objects.append(f'\t\t{ident(name)} = {{ {text} }};')
files = sorted((ROOT / 'WerkstattApp').glob('*.swift'))
ui_files = sorted((ROOT / 'WerkstattUITests').glob('*.swift'))
for f in ui_files:
    add('ui-file:'+f.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(f.name)}; sourceTree = "<group>";')
    add('ui-build:'+f.name, f'isa = PBXBuildFile; fileRef = {ident("ui-file:"+f.name)};')
add('ui-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = WerkstattUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
add('ui-group', 'isa = PBXGroup; children = (' + ','.join(ident('ui-file:'+f.name) for f in ui_files) + ',); path = WerkstattUITests; sourceTree = "<group>";')
add('ui-sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(ident('ui-build:'+f.name) for f in ui_files) + ',); runOnlyForDeploymentPostprocessing = 0;')
add('ui-frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add('ui-proxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("target")}; remoteInfo = Werkstatt;')
add('ui-dependency', f'isa = PBXTargetDependency; target = {ident("target")}; targetProxy = {ident("ui-proxy")};')
for f in files:
    add('file:'+f.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(f.name)}; sourceTree = "<group>";')
    add('build:'+f.name, f'isa = PBXBuildFile; fileRef = {ident("file:"+f.name)};')
add('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
add('assets-build', f'isa = PBXBuildFile; fileRef = {ident("assets")};')
add('privacy', 'isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = \"<group>\";')
add('privacy-build', f'isa = PBXBuildFile; fileRef = {ident("privacy")};')
add('info', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Werkstatt.app; sourceTree = BUILT_PRODUCTS_DIR;')
add('package', 'isa = XCLocalSwiftPackageReference; relativePath = WerkstattCore;')
add('package-product', f'isa = XCSwiftPackageProductDependency; package = {ident("package")}; productName = WerkstattCore;')
add('package-build', f'isa = PBXBuildFile; productRef = {ident("package-product")};')
add('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({ident("package-build")},); runOnlyForDeploymentPostprocessing = 0;')
add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ident("assets-build")},{ident("privacy-build")},); runOnlyForDeploymentPostprocessing = 0;')
add('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(ident('build:'+f.name) for f in files) + ',); runOnlyForDeploymentPostprocessing = 0;')
add('app-group', 'isa = PBXGroup; children = (' + ','.join(ident('file:'+f.name) for f in files) + f',{ident("assets")},{ident("info")},{ident("privacy")},); path = WerkstattApp; sourceTree = "<group>";')
add('products-group', f'isa = PBXGroup; children = ({ident("product")},{ident("ui-product")},); name = Products; sourceTree = "<group>";')
add('main-group', f'isa = PBXGroup; children = ({ident("app-group")},{ident("ui-group")},{ident("products-group")},); sourceTree = "<group>";')
for kind in ('Debug', 'Release'):
    add('project-'+kind, f'isa = XCBuildConfiguration; name = {kind}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; ENABLE_USER_SCRIPT_SANDBOXING = YES; }};')
    settings = {
        'PRODUCT_BUNDLE_IDENTIFIER': 'com.caramiarosien.Werkstatt', 'PRODUCT_NAME':'Werkstatt',
        'INFOPLIST_FILE':'WerkstattApp/Info.plist', 'GENERATE_INFOPLIST_FILE':'NO',
        'CODE_SIGN_STYLE':'Automatic', 'DEVELOPMENT_TEAM':'', 'TARGETED_DEVICE_FAMILY':'1',
        'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST':'NO',
        'IPHONEOS_DEPLOYMENT_TARGET':'17.0', 'SWIFT_VERSION':'5.0', 'MARKETING_VERSION':'1.0',
        'CURRENT_PROJECT_VERSION':'1', 'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon',
        'ENABLE_PREVIEWS':'YES', 'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks',
        'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if kind=='Debug' else '-O',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if kind=='Debug' else '',
        'ONLY_ACTIVE_ARCH':'YES' if kind=='Debug' else 'NO',
    }
    add('target-'+kind, f'isa = XCBuildConfiguration; name = {kind}; buildSettings = {{ '+' '.join(f'{k} = {quoted(v)};' for k,v in settings.items())+' };')
    ui_settings = {
        'PRODUCT_BUNDLE_IDENTIFIER': 'com.caramiarosien.WerkstattUITests',
        'PRODUCT_NAME': 'WerkstattUITests', 'GENERATE_INFOPLIST_FILE': 'YES',
        'TEST_TARGET_NAME': 'Werkstatt', 'TARGETED_DEVICE_FAMILY': '1',
        'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SWIFT_VERSION': '5.0',
        'CODE_SIGN_STYLE': 'Automatic', 'DEVELOPMENT_TEAM': '',
        'ONLY_ACTIVE_ARCH': 'YES' if kind == 'Debug' else 'NO',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
    }
    add('ui-'+kind, f'isa = XCBuildConfiguration; name = {kind}; buildSettings = {{ '+' '.join(f'{k} = {quoted(v)};' for k,v in ui_settings.items())+' };')
for prefix in ('project','target','ui'):
    add(prefix+'-config', f'isa = XCConfigurationList; buildConfigurations = ({ident(prefix+"-Debug")},{ident(prefix+"-Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('target', f'isa = PBXNativeTarget; name = Werkstatt; productName = Werkstatt; productType = "com.apple.product-type.application"; productReference = {ident("product")}; buildConfigurationList = {ident("target-config")}; buildPhases = ({ident("sources")},{ident("frameworks")},{ident("resources")},); buildRules = (); dependencies = (); packageProductDependencies = ({ident("package-product")},);')
add('ui-target', f'isa = PBXNativeTarget; name = WerkstattUITests; productName = WerkstattUITests; productType = "com.apple.product-type.bundle.ui-testing"; productReference = {ident("ui-product")}; buildConfigurationList = {ident("ui-config")}; buildPhases = ({ident("ui-sources")},{ident("ui-frameworks")},); buildRules = (); dependencies = ({ident("ui-dependency")},);')
add('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; TargetAttributes = {{ {ident("target")} = {{ CreatedOnToolsVersion = 16.0; }}; {ident("ui-target")} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {ident("target")}; }}; }}; }}; buildConfigurationList = {ident("project-config")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = de; knownRegions = (de,en,Base,); mainGroup = {ident("main-group")}; productRefGroup = {ident("products-group")}; projectDirPath = ""; projectRoot = ""; targets = ({ident("target")},{ident("ui-target")},); packageReferences = ({ident("package")},);')
project = ROOT / 'WerkstattApp.xcodeproj'
project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'+'\n'.join(objects)+f'\n\t}};\n\trootObject = {ident("project")};\n}}\n')
scheme_folder = project/'xcshareddata/xcschemes';scheme_folder.mkdir(parents=True,exist_ok=True)
reference=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target")}" BuildableName="Werkstatt.app" BlueprintName="Werkstatt" ReferencedContainer="container:WerkstattApp.xcodeproj"/>'
ui_reference=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("ui-target")}" BuildableName="WerkstattUITests.xctest" BlueprintName="WerkstattUITests" ReferencedContainer="container:WerkstattApp.xcodeproj"/>'
(scheme_folder/'Werkstatt.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO">{ui_reference}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(project)
