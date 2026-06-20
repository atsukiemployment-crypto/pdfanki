#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Capacitor へのプラグイン登録。JS から Capacitor.Plugins.PencilKitPlugin が見えるようになる。
CAP_PLUGIN(PencilKitPlugin, "PencilKitPlugin",
  CAP_PLUGIN_METHOD(open, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(close, CAPPluginReturnPromise);
)
