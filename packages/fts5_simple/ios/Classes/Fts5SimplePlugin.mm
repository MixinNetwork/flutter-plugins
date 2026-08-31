#import "Fts5SimplePlugin.h"
#import <sqlite3.h>

#ifdef __cplusplus
extern "C" {
#endif

void sqlite3_simple_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi);

#ifdef __cplusplus
}
#endif


void loadExtension() {
  sqlite3_auto_extension((void (*)(void)) sqlite3_simple_init);
}


@implementation Fts5SimplePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  loadExtension();
}
@end

