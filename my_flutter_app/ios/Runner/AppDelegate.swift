import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Check for fresh install and cleanup any remaining data
    checkAndCleanupOnFreshInstall()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  /// بررسی و پاکسازی داده‌های باقی‌مانده در صورت fresh install
  private func checkAndCleanupOnFreshInstall() {
    // این متد در iOS به صورت خودکار اجرا می‌شود
    // زیرا iOS هنگام حذف اپلیکیشن تمام داده‌ها را پاک می‌کند
    print("🔍 iOS: Checking for fresh install...")
    
    // بررسی وجود داده‌های باقی‌مانده
    if hasRemainingData() {
      print("⚠️ iOS: Remaining data detected, performing cleanup...")
      performCompleteCleanup()
    } else {
      print("✅ iOS: No remaining data found - clean fresh install")
    }
  }
  
  /// بررسی وجود داده‌های باقی‌مانده
  private func hasRemainingData() -> Bool {
    let userDefaults = UserDefaults.standard
    let keys = userDefaults.dictionaryRepresentation().keys
    
    // بررسی وجود کلیدهای مربوط به اپلیکیشن
    let appKeys = keys.filter { key in
      key.contains("Flutter") ||
      key.contains("flutter") ||
      key.contains("passcode") ||
      key.contains("wallet") ||
      key.contains("token") ||
      key.contains("price") ||
      key.contains("currency") ||
      key.contains("language")
    }
    
    return !appKeys.isEmpty
  }
  
  /// پاکسازی کامل تمام داده‌ها
  private func performCompleteCleanup() {
    print("🗑️ iOS: Starting complete data cleanup...")
    
    // پاکسازی UserDefaults
    clearUserDefaults()
    
    // پاکسازی فایل‌های کش
    clearCacheFiles()
    
    // پاکسازی فایل‌های Documents
    clearDocumentsFiles()
    
    print("✅ iOS: Complete data cleanup finished")
  }
  
  /// پاکسازی UserDefaults
  private func clearUserDefaults() {
    let userDefaults = UserDefaults.standard
    let keys = userDefaults.dictionaryRepresentation().keys
    
    for key in keys {
      userDefaults.removeObject(forKey: key)
    }
    
    userDefaults.synchronize()
    print("✅ iOS: UserDefaults cleared")
  }
  
  /// پاکسازی فایل‌های کش
  private func clearCacheFiles() {
    let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    if let cacheURL = cacheURL {
      do {
        let cacheContents = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
        for fileURL in cacheContents {
          try FileManager.default.removeItem(at: fileURL)
        }
        print("✅ iOS: Cache files cleared")
      } catch {
        print("❌ iOS: Error clearing cache files: \(error)")
      }
    }
  }
  
  /// پاکسازی فایل‌های Documents
  private func clearDocumentsFiles() {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    if let documentsURL = documentsURL {
      do {
        let documentsContents = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
        for fileURL in documentsContents {
          try FileManager.default.removeItem(at: fileURL)
        }
        print("✅ iOS: Documents files cleared")
      } catch {
        print("❌ iOS: Error clearing documents files: \(error)")
      }
    }
  }
}
