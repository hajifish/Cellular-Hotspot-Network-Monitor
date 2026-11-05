#import "TMNotify.h"
#import <AppKit/AppKit.h>

// NSUserNotification 于 macOS 11 起标记过时；系统运行时保留（macOS 26 实测可用）。
// 与 mac-notification-sys 相同：编译期压掉过时警告，不做运行时反射。
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static void (*g_tm_activation_handler)(const char *, int) = NULL;

@interface TMNotifyDelegate : NSObject <NSUserNotificationCenterDelegate>
@end

@implementation TMNotifyDelegate
// 点击/操作通知时回调（AppKit 保证主线程）
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
        didActivateNotification:(NSUserNotification *)notification {
    if (g_tm_activation_handler == NULL) return;
    const char *identifier = notification.identifier.UTF8String;
    g_tm_activation_handler(identifier != NULL ? identifier : "",
                            (int)notification.activationType);
}
@end

static TMNotifyDelegate *g_tm_delegate = nil;

bool tm_notification_available(void) {
    return NSClassFromString(@"NSUserNotificationCenter") != nil
        && NSClassFromString(@"NSUserNotification") != nil;
}

void tm_post_notification(const char *title, const char *body,
                          const char *identifier, bool sound) {
    if (!tm_notification_available()) return;
    @autoreleasepool {
        NSUserNotification *note = [[NSUserNotification alloc] init];
        note.title = [NSString stringWithUTF8String:title ?: ""];
        note.informativeText = [NSString stringWithUTF8String:body ?: ""];
        if (identifier != NULL) {
            note.identifier = [NSString stringWithUTF8String:identifier];
        }
        if (sound) {
            note.soundName = NSUserNotificationDefaultSoundName;
        }
        // 裸二进制（无 bundle）时 center 为 nil，objc 向 nil 发消息＝安全 no-op
        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:note];
    }
}

void tm_set_activation_handler(void (*handler)(const char *, int)) {
    g_tm_activation_handler = handler;
    if (g_tm_delegate == nil) {
        g_tm_delegate = [[TMNotifyDelegate alloc] init];
    }
    [NSUserNotificationCenter defaultUserNotificationCenter].delegate = g_tm_delegate;
}
