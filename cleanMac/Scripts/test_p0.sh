#!/bin/bash
# 独立运行P0/P1 核心模型和文件系统回归测试，不依赖签名、应用授权或真实缓存内容。
set -euo pipefail
cd "$(dirname "$0")/.."
P0_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cleanmac-p0-tests.XXXXXX")
trap 'rm -rf "$P0_TEST_DIR"' EXIT
P0_XCODE_DIR=$(xcode-select -p)
P0_PLATFORM_DIR="$P0_XCODE_DIR/Platforms/MacOSX.platform/Developer"
P0_FRAMEWORK_DIR="$P0_PLATFORM_DIR/Library/Frameworks"
P0_LIBRARY_DIR="$P0_PLATFORM_DIR/usr/lib"

swiftc -emit-library -emit-module -enable-testing -module-name cleanMac \
  -emit-module-path "$P0_TEST_DIR/cleanMac.swiftmodule" -o "$P0_TEST_DIR/libcleanMac.dylib" \
  cleanMac/Models/{FileItem,FileStorageMeasurement,CacheRuleCatalog,CacheApplication,BrowserCacheApplication,ScanCategory,ScanDiagnostics,ScanResult,LocalInspection,ApplicationResourceUsage,DeviceTelemetry}.swift \
  cleanMac/Helpers/{FileHelper,FileSizeFormatter}.swift \
  cleanMac/Services/{ScanFileAccess,ScanPathOwnership,CleaningHistoryStore,CleanService,PrivilegedTrashService,DeleteDryRun,ApplicationNameResolver,ApplicationCacheScanner,AppLeftoverScanner,ApplicationUninstallPreflight,CacheRuleStore,CacheScanIgnoreStore,DiskBubbleLayout,DiskMapSelectionPolicy,SafetyWhitelist,UserWhitelist,AppLog,SmartCleanService,StartupInspectionService,BrowserPrivacyService,ExtensionInventoryService,CacheEventMonitor,CacheScanIndex,LocalSpaceInsights,DuplicateFileScanner}.swift

cat > "$P0_TEST_DIR/main.swift" <<'SWIFT'
import XCTest
let suite = XCTestSuite(name: "P0 and regression")
suite.addTest(ScanDiagnosticsTests.defaultTestSuite)
suite.addTest(ApplicationCacheScannerTests.defaultTestSuite)
suite.addTest(DiskMapSelectionPolicyTests.defaultTestSuite)
suite.addTest(DiskBubbleLayoutTests.defaultTestSuite)
suite.addTest(StorageAccountingTests.defaultTestSuite)
suite.addTest(CleaningHistoryTests.defaultTestSuite)
suite.addTest(CacheRuleTests.defaultTestSuite)
suite.addTest(AppUninstallAssociationTests.defaultTestSuite)
suite.addTest(RemainingPlanTests.defaultTestSuite)
suite.addTest(DeviceTelemetryTests.defaultTestSuite)
suite.run()
guard let result = suite.testRun, result.executionCount == 138, result.totalFailureCount == 0 else { exit(1) }
SWIFT

swiftc -I "$P0_TEST_DIR" -I "$P0_LIBRARY_DIR" -L "$P0_TEST_DIR" -L "$P0_LIBRARY_DIR" -lcleanMac \
  -F "$P0_FRAMEWORK_DIR" \
  -Xlinker -rpath -Xlinker "$P0_TEST_DIR" \
  -Xlinker -rpath -Xlinker "$P0_FRAMEWORK_DIR" \
  -Xlinker -rpath -Xlinker "$P0_LIBRARY_DIR" \
  cleanMacTests/{ScanDiagnosticsTests,ApplicationCacheScannerTests,DiskMapSelectionPolicyTests,DiskBubbleLayoutTests,StorageAccountingTests,CleaningHistoryTests,CacheRuleTests,AppUninstallAssociationTests,RemainingPlanTests,DeviceTelemetryTests}.swift \
  "$P0_TEST_DIR/main.swift" -o "$P0_TEST_DIR/tests"
"$P0_TEST_DIR/tests"
