#ifndef TMNOTIFY_H
#define TMNOTIFY_H
#include <stdbool.h>

/// NSUserNotification 老通知接口桥（照抄 mac-notification-sys 0.6.15 objc/notify.m 机制）。
/// 该接口对 clang 编译期可见、对 Swift 模块不可见，故须经 ObjC 桥 target 转接。
/// 老接口通知按应用 bundle 归属、横幅自带应用图标，无证书要求（2026-11-05 实验证实）。

/// 老接口运行时是否可用（Apple 未来移除时的检测点）
bool tm_notification_available(void);

/// 投递一条系统通知（title/body/identifier 均为 UTF-8 C 字符串；sound 播放系统默认音）
void tm_post_notification(const char *title, const char *body,
                          const char *identifier, bool sound);

/// 注册通知点击回调（identifier 为通知标识，activation_type 为 NSUserNotificationActivationType 原始值）
void tm_set_activation_handler(void (*handler)(const char *identifier, int activation_type));

#endif /* TMNOTIFY_H */
