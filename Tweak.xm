#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <sqlite3.h>
#include <stdlib.h>

#pragma mark - Globals

static UIWindow *debugWindow = nil;
static UIButton *menuButton = nil;
static UIView *panel = nil;
static UITextField *scoreField = nil;
static UILabel *scoreInfoLabel = nil;
static UILabel *statusLabel = nil;

static BOOL menuHiddenMode = NO;
static CGPoint menuDragStartPoint;
static CGPoint menuOriginalCenter;

static UITapGestureRecognizer *screenDoubleTapGesture = nil;

#pragma mark - Helpers

static UIColor *rgba(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r / 255.0
                           green:g / 255.0
                            blue:b / 255.0
                           alpha:a];
}

static NSString *docsPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths firstObject];
}

static void setStatus(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (statusLabel) {
            statusLabel.text = text ?: @"";
        }
    });
}

static void setScoreInfo(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (scoreInfoLabel) {
            scoreInfoLabel.text = text ?: @"High: --   Current: --";
        }
    });
}

static void saveMenuPosition(CGPoint center) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:center.x forKey:@"ScoreToolsMenuCenterX"];
    [defaults setDouble:center.y forKey:@"ScoreToolsMenuCenterY"];
    [defaults synchronize];
}

static CGPoint loadMenuPosition(CGRect screen) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    double x = [defaults doubleForKey:@"ScoreToolsMenuCenterX"];
    double y = [defaults doubleForKey:@"ScoreToolsMenuCenterY"];

    if (x <= 0 || y <= 0) {
        return CGPointMake(52, 96);
    }

    CGFloat minX = 34;
    CGFloat maxX = screen.size.width - 34;
    CGFloat minY = 45;
    CGFloat maxY = screen.size.height - 45;

    x = MAX(minX, MIN(maxX, x));
    y = MAX(minY, MIN(maxY, y));

    return CGPointMake(x, y);
}

static void keepMenuButtonOnScreen(void) {
    if (!menuButton) {
        return;
    }

    CGRect screen = [UIScreen mainScreen].bounds;

    CGFloat halfW = menuButton.bounds.size.width / 2.0;
    CGFloat halfH = menuButton.bounds.size.height / 2.0;

    CGFloat x = MAX(halfW + 6, MIN(screen.size.width - halfW - 6, menuButton.center.x));
    CGFloat y = MAX(halfH + 20, MIN(screen.size.height - halfH - 20, menuButton.center.y));

    menuButton.center = CGPointMake(x, y);
}

static void positionPanelNearMenu(void) {
    if (!menuButton || !panel) {
        return;
    }

    CGRect screen = [UIScreen mainScreen].bounds;

    CGFloat panelW = panel.bounds.size.width;
    CGFloat panelH = panel.bounds.size.height;

    CGFloat x = menuButton.center.x - 34;
    CGFloat y = CGRectGetMaxY(menuButton.frame) + 10;

    if (y + panelH > screen.size.height - 20) {
        y = CGRectGetMinY(menuButton.frame) - panelH - 10;
    }

    x = MAX(10, MIN(screen.size.width - panelW - 10, x));
    y = MAX(30, MIN(screen.size.height - panelH - 20, y));

    panel.frame = CGRectMake(x, y, panelW, panelH);
}

static void showMenuButton(void) {
    if (!menuButton) {
        return;
    }

    menuHiddenMode = NO;

    menuButton.alpha = 1.0;
    menuButton.backgroundColor = rgba(10, 15, 13, 0.88);
    menuButton.layer.borderColor = rgba(85, 255, 165, 0.80).CGColor;
    menuButton.layer.shadowOpacity = 0.45;
    [menuButton setTitle:@"MENU" forState:UIControlStateNormal];

    setStatus(@"MENU SHOWN");
}

static void hideMenuButton(void) {
    if (!menuButton) {
        return;
    }

    menuHiddenMode = YES;

    if (panel) {
        panel.hidden = YES;
    }

    menuButton.alpha = 0.12;
    menuButton.backgroundColor = [UIColor clearColor];
    menuButton.layer.borderColor = [UIColor clearColor].CGColor;
    menuButton.layer.shadowOpacity = 0.0;
    [menuButton setTitle:@"" forState:UIControlStateNormal];
}

#pragma mark - Pass-through views

@interface DebugPassThroughView : UIView
@end

@implementation DebugPassThroughView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];

    if (hitView == self) {
        return nil;
    }

    return hitView;
}

@end

@interface DebugPassThroughWindow : UIWindow
@end

@implementation DebugPassThroughWindow

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (menuButton && !menuButton.hidden) {
        CGPoint buttonPoint = [menuButton convertPoint:point fromView:self];

        if ([menuButton pointInside:buttonPoint withEvent:event]) {
            return YES;
        }
    }

    if (panel && !panel.hidden) {
        CGPoint panelPoint = [panel convertPoint:point fromView:self];

        if ([panel pointInside:panelPoint withEvent:event]) {
            return YES;
        }
    }

    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (![self pointInside:point withEvent:event]) {
        return nil;
    }

    return [super hitTest:point withEvent:event];
}

@end

#pragma mark - SQLite helpers

static NSString *readSqliteValue(sqlite3 *db, NSString *key) {
    sqlite3_stmt *stmt = NULL;
    const char *sql = "SELECT value FROM data WHERE key=?";

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return nil;
    }

    sqlite3_bind_text(stmt, 1, [key UTF8String], -1, SQLITE_TRANSIENT);

    NSString *value = nil;

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *text = sqlite3_column_text(stmt, 0);

        if (text) {
            value = [NSString stringWithUTF8String:(const char *)text];
        }
    }

    sqlite3_finalize(stmt);
    return value;
}

static BOOL updateSqliteValue(sqlite3 *db, NSString *key, NSString *value) {
    sqlite3_stmt *stmt = NULL;
    const char *sql = "UPDATE data SET value=? WHERE key=?";

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return NO;
    }

    sqlite3_bind_text(stmt, 1, [value UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [key UTF8String], -1, SQLITE_TRANSIENT);

    BOOL ok = sqlite3_step(stmt) == SQLITE_DONE;

    sqlite3_finalize(stmt);
    return ok;
}

#pragma mark - Score read/check

static NSDictionary *readScoreProfile(void) {
    NSString *dbPath = [docsPath() stringByAppendingPathComponent:@"jsb.sqlite"];

    sqlite3 *db = NULL;

    if (sqlite3_open([dbPath UTF8String], &db) != SQLITE_OK) {
        return nil;
    }

    NSString *raw = readSqliteValue(db, @"fangkuaipintu");
    sqlite3_close(db);

    if (!raw) {
        return nil;
    }

    NSData *jsonData = [raw dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *profile = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];

    if (![profile isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    return profile;
}

static void checkScore(void) {
    NSDictionary *profile = readScoreProfile();

    if (!profile) {
        setScoreInfo(@"High: --   Current: --");
        setStatus(@"Could not read score");
        return;
    }

    NSNumber *high = profile[@"high_cord"];
    NSNumber *current = profile[@"current_cord"];

    setScoreInfo([NSString stringWithFormat:@"High: %@   Current: %@",
                  high ?: @-1,
                  current ?: @-1]);

    setStatus(@"Score checked");
}

#pragma mark - Score patching

static BOOL patchScore(NSInteger targetScore, NSString **messageOut) {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *docs = docsPath();
    NSString *originalPath = [docs stringByAppendingPathComponent:@"jsb.sqlite"];
    NSString *patchPath = [docs stringByAppendingPathComponent:@"jsb.sqlite.patch"];

    long long timestamp = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
    NSString *backupName = [NSString stringWithFormat:@"jsb.sqlite.backup_%lld", timestamp];
    NSString *backupPath = [docs stringByAppendingPathComponent:backupName];

    if (![fm fileExistsAtPath:originalPath]) {
        if (messageOut) {
            *messageOut = @"Score file not found";
        }
        return NO;
    }

    [fm removeItemAtPath:patchPath error:nil];

    NSError *copyError = nil;

    if (![fm copyItemAtPath:originalPath toPath:patchPath error:&copyError]) {
        if (messageOut) {
            *messageOut = [NSString stringWithFormat:@"Could not copy score file: %@", copyError.localizedDescription];
        }
        return NO;
    }

    sqlite3 *db = NULL;

    if (sqlite3_open([patchPath UTF8String], &db) != SQLITE_OK) {
        if (messageOut) {
            *messageOut = @"Could not open score file";
        }
        return NO;
    }

    NSString *key = @"fangkuaipintu";
    NSString *raw = readSqliteValue(db, key);

    if (!raw) {
        sqlite3_close(db);

        if (messageOut) {
            *messageOut = @"Score profile not found";
        }

        return NO;
    }

    NSData *jsonData = [raw dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError = nil;

    NSMutableDictionary *profile = [[NSJSONSerialization JSONObjectWithData:jsonData
                                                                    options:NSJSONReadingMutableContainers
                                                                      error:&jsonError] mutableCopy];

    if (!profile || jsonError) {
        sqlite3_close(db);

        if (messageOut) {
            *messageOut = @"Could not read score data";
        }

        return NO;
    }

    profile[@"high_cord"] = @(targetScore);
    profile[@"current_cord"] = @(targetScore);

    NSError *writeJsonError = nil;

    NSData *patchedData = [NSJSONSerialization dataWithJSONObject:profile
                                                          options:0
                                                            error:&writeJsonError];

    if (!patchedData || writeJsonError) {
        sqlite3_close(db);

        if (messageOut) {
            *messageOut = @"Could not save score data";
        }

        return NO;
    }

    NSString *patchedRaw = [[NSString alloc] initWithData:patchedData encoding:NSUTF8StringEncoding];

    if (!updateSqliteValue(db, key, patchedRaw)) {
        sqlite3_close(db);

        if (messageOut) {
            *messageOut = @"Could not update score file";
        }

        return NO;
    }

    NSString *verifyRaw = readSqliteValue(db, key);
    sqlite3_close(db);

    if (!verifyRaw) {
        if (messageOut) {
            *messageOut = @"Could not verify score";
        }

        return NO;
    }

    NSData *verifyData = [verifyRaw dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *verifyProfile = [NSJSONSerialization JSONObjectWithData:verifyData options:0 error:nil];
    NSNumber *verifyHigh = verifyProfile[@"high_cord"];

    if (![verifyHigh isKindOfClass:[NSNumber class]] || [verifyHigh integerValue] != targetScore) {
        if (messageOut) {
            *messageOut = @"Score did not update";
        }

        return NO;
    }

    [fm copyItemAtPath:originalPath toPath:backupPath error:nil];

    [fm removeItemAtPath:[originalPath stringByAppendingString:@"-wal"] error:nil];
    [fm removeItemAtPath:[originalPath stringByAppendingString:@"-shm"] error:nil];

    NSError *removeError = nil;

    if (![fm removeItemAtPath:originalPath error:&removeError]) {
        if (messageOut) {
            *messageOut = [NSString stringWithFormat:@"Could not replace old score: %@", removeError.localizedDescription];
        }

        return NO;
    }

    NSError *moveError = nil;

    if (![fm moveItemAtPath:patchPath toPath:originalPath error:&moveError]) {
        if (messageOut) {
            *messageOut = [NSString stringWithFormat:@"Could not move new score: %@", moveError.localizedDescription];
        }

        return NO;
    }

    if (messageOut) {
        *messageOut = [NSString stringWithFormat:@"Saved score: %ld. Reloading.", (long)targetScore];
    }

    return YES;
}

#pragma mark - Restore last score

static NSString *latestBackupPath(void) {
    NSString *docs = docsPath();
    NSFileManager *fm = [NSFileManager defaultManager];

    NSArray *files = [fm contentsOfDirectoryAtPath:docs error:nil];

    NSString *latest = nil;

    for (NSString *file in files) {
        if ([file hasPrefix:@"jsb.sqlite.backup_"]) {
            if (!latest || [file compare:latest options:NSNumericSearch] == NSOrderedDescending) {
                latest = file;
            }
        }
    }

    if (!latest) {
        return nil;
    }

    return [docs stringByAppendingPathComponent:latest];
}

static void restoreLastScore(void) {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *docs = docsPath();
    NSString *originalPath = [docs stringByAppendingPathComponent:@"jsb.sqlite"];
    NSString *backupPath = latestBackupPath();

    if (!backupPath) {
        setStatus(@"No previous score found");
        return;
    }

    [fm removeItemAtPath:[originalPath stringByAppendingString:@"-wal"] error:nil];
    [fm removeItemAtPath:[originalPath stringByAppendingString:@"-shm"] error:nil];
    [fm removeItemAtPath:originalPath error:nil];

    NSError *copyError = nil;
    BOOL ok = [fm copyItemAtPath:backupPath toPath:originalPath error:&copyError];

    if (!ok) {
        setStatus([NSString stringWithFormat:@"Could not undo: %@", copyError.localizedDescription]);
        return;
    }

    setStatus(@"Last change undone");
    checkScore();
}

#pragma mark - Actions

@interface ScoreToolsActions : NSObject
+ (instancetype)shared;
- (void)handleMenuSingleTap:(UITapGestureRecognizer *)gesture;
- (void)handleMenuDoubleTap:(UITapGestureRecognizer *)gesture;
- (void)handleScreenDoubleTap:(UITapGestureRecognizer *)gesture;
- (void)handleMenuLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)togglePanel;
- (void)setPreset1000;
- (void)setPreset5000;
- (void)setPreset10000;
- (void)saveAndReload;
- (void)checkScoreButton;
- (void)resetScore;
- (void)undoChange;
- (void)hideMenu;
@end

@implementation ScoreToolsActions

+ (instancetype)shared {
    static ScoreToolsActions *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [ScoreToolsActions new];
    });

    return sharedInstance;
}

- (void)handleMenuSingleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    if (menuHiddenMode) {
        return;
    }

    [self togglePanel];
}

- (void)handleMenuDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    showMenuButton();

    if (panel) {
        positionPanelNearMenu();
        panel.hidden = NO;
        checkScore();
        setStatus(@"READY");
    }
}

- (void)handleScreenDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    showMenuButton();

    if (panel) {
        positionPanelNearMenu();
        panel.hidden = NO;
        checkScore();
        setStatus(@"READY");
    }
}

- (void)handleMenuLongPress:(UILongPressGestureRecognizer *)gesture {
    if (!menuButton) {
        return;
    }

    CGPoint touchPoint = [gesture locationInView:debugWindow];

    if (gesture.state == UIGestureRecognizerStateBegan) {
        menuDragStartPoint = touchPoint;
        menuOriginalCenter = menuButton.center;

        showMenuButton();
        setStatus(@"Drag MENU");
    }

    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat dx = touchPoint.x - menuDragStartPoint.x;
        CGFloat dy = touchPoint.y - menuDragStartPoint.y;

        menuButton.center = CGPointMake(menuOriginalCenter.x + dx,
                                        menuOriginalCenter.y + dy);

        keepMenuButtonOnScreen();

        if (panel && !panel.hidden) {
            positionPanelNearMenu();
        }
    }

    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        keepMenuButtonOnScreen();
        saveMenuPosition(menuButton.center);

        if (panel && !panel.hidden) {
            positionPanelNearMenu();
        }

        setStatus(@"MENU moved");
    }
}

- (void)togglePanel {
    if (!panel) {
        return;
    }

    if (menuHiddenMode) {
        showMenuButton();
        return;
    }

    positionPanelNearMenu();

    panel.hidden = !panel.hidden;

    if (!panel.hidden) {
        checkScore();
        setStatus(@"READY");
    }
}

- (void)setPreset1000 {
    scoreField.text = @"1000";
    setStatus(@"Preset selected: 1K");
}

- (void)setPreset5000 {
    scoreField.text = @"5000";
    setStatus(@"Preset selected: 5K");
}

- (void)setPreset10000 {
    scoreField.text = @"10000";
    setStatus(@"Preset selected: 10K");
}

- (void)saveAndReload {
    NSInteger score = [scoreField.text integerValue];

    if (score < 0) {
        setStatus(@"Enter a valid score");
        return;
    }

    [scoreField resignFirstResponder];
    setStatus(@"Saving score...");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *msg = nil;
        BOOL ok = patchScore(score, &msg);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                setStatus(msg ?: @"Saved. Reloading.");
                checkScore();

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    exit(0);
                });
            } else {
                setStatus([NSString stringWithFormat:@"Could not save: %@", msg ?: @"unknown"]);
            }
        });
    });
}

- (void)checkScoreButton {
    [scoreField resignFirstResponder];
    checkScore();
}

- (void)resetScore {
    scoreField.text = @"0";
    setStatus(@"Reset selected. Tap SAVE + RELOAD.");
}

- (void)undoChange {
    [scoreField resignFirstResponder];
    restoreLastScore();
}

- (void)hideMenu {
    [scoreField resignFirstResponder];
    hideMenuButton();
}

@end

#pragma mark - Screen double tap attachment

static UIWindow *findAppWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene = (UIWindowScene *)scene;

            for (UIWindow *window in windowScene.windows) {
                if (window != debugWindow && !window.hidden && window.alpha > 0.01) {
                    return window;
                }
            }
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (window != debugWindow && !window.hidden && window.alpha > 0.01) {
                return window;
            }
        }
#pragma clang diagnostic pop
    }

    return nil;
}

static void attachScreenDoubleTapGesture(void) {
    UIWindow *appWindow = findAppWindow();

    if (!appWindow || screenDoubleTapGesture) {
        return;
    }

    screenDoubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:[ScoreToolsActions shared]
                                                                     action:@selector(handleScreenDoubleTap:)];

    screenDoubleTapGesture.numberOfTapsRequired = 2;
    screenDoubleTapGesture.cancelsTouchesInView = NO;
    screenDoubleTapGesture.delaysTouchesBegan = NO;
    screenDoubleTapGesture.delaysTouchesEnded = NO;

    [appWindow addGestureRecognizer:screenDoubleTapGesture];
}

#pragma mark - UI

static UIButton *makeButton(CGRect frame, NSString *title, UIColor *color, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];

    button.frame = frame;
    button.backgroundColor = color;
    button.layer.cornerRadius = 12;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = rgba(255, 255, 255, 0.10).CGColor;
    button.layer.shadowColor = color.CGColor;
    button.layer.shadowOpacity = 0.22;
    button.layer.shadowRadius = 10;
    button.layer.shadowOffset = CGSizeMake(0, 4);

    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    UIFont *font = [UIFont fontWithName:@"Menlo-Bold" size:11];
    button.titleLabel.font = font ?: [UIFont boldSystemFontOfSize:11];

    [button addTarget:[ScoreToolsActions shared]
               action:action
     forControlEvents:UIControlEventTouchUpInside];

    return button;
}

static void createDebugUI(void) {
    if (debugWindow) {
        return;
    }

    CGRect screen = [UIScreen mainScreen].bounds;

    debugWindow = [[DebugPassThroughWindow alloc] initWithFrame:screen];
    debugWindow.windowLevel = UIWindowLevelAlert + 1000;
    debugWindow.backgroundColor = [UIColor clearColor];
    debugWindow.hidden = NO;

    UIViewController *vc = [UIViewController new];

    DebugPassThroughView *passView = [[DebugPassThroughView alloc] initWithFrame:screen];
    passView.backgroundColor = [UIColor clearColor];

    vc.view = passView;
    debugWindow.rootViewController = vc;

    menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    menuButton.frame = CGRectMake(0, 0, 68, 40);
    menuButton.center = loadMenuPosition(screen);
    menuButton.backgroundColor = rgba(10, 15, 13, 0.88);
    menuButton.layer.cornerRadius = 14;
    menuButton.layer.borderColor = rgba(85, 255, 165, 0.80).CGColor;
    menuButton.layer.borderWidth = 1.0;
    menuButton.layer.shadowColor = rgba(85, 255, 165, 1.0).CGColor;
    menuButton.layer.shadowOpacity = 0.45;
    menuButton.layer.shadowRadius = 14;
    menuButton.layer.shadowOffset = CGSizeMake(0, 0);

    [menuButton setTitle:@"MENU" forState:UIControlStateNormal];
    [menuButton setTitleColor:rgba(175, 255, 205, 1.0) forState:UIControlStateNormal];

    UIFont *menuFont = [UIFont fontWithName:@"Menlo-Bold" size:12];
    menuButton.titleLabel.font = menuFont ?: [UIFont boldSystemFontOfSize:12];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:[ScoreToolsActions shared]
                                                                                action:@selector(handleMenuSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    singleTap.cancelsTouchesInView = YES;

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:[ScoreToolsActions shared]
                                                                                action:@selector(handleMenuDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.cancelsTouchesInView = YES;

    [singleTap requireGestureRecognizerToFail:doubleTap];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:[ScoreToolsActions shared]
                                                                                            action:@selector(handleMenuLongPress:)];
    longPress.minimumPressDuration = 0.45;
    longPress.cancelsTouchesInView = YES;

    [menuButton addGestureRecognizer:singleTap];
    [menuButton addGestureRecognizer:doubleTap];
    [menuButton addGestureRecognizer:longPress];

    [vc.view addSubview:menuButton];

    panel = [[UIView alloc] initWithFrame:CGRectMake(18, 126, 318, 356)];
    panel.backgroundColor = rgba(8, 12, 11, 0.94);
    panel.layer.cornerRadius = 22;
    panel.layer.borderColor = rgba(85, 255, 165, 0.28).CGColor;
    panel.layer.borderWidth = 1.0;
    panel.layer.shadowColor = rgba(0, 0, 0, 1.0).CGColor;
    panel.layer.shadowOpacity = 0.55;
    panel.layer.shadowRadius = 22;
    panel.layer.shadowOffset = CGSizeMake(0, 12);
    panel.hidden = YES;

    [vc.view addSubview:panel];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(18, 18, 282, 30)];
    title.text = @"SCORE TOOLS";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont fontWithName:@"Menlo-Bold" size:22] ?: [UIFont boldSystemFontOfSize:22];
    [panel addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(18, 48, 282, 18)];
    subtitle.text = @"Saved score controls";
    subtitle.textColor = rgba(210, 255, 225, 0.58);
    subtitle.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    [panel addSubview:subtitle];

    scoreInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 76, 282, 20)];
    scoreInfoLabel.text = @"High: --   Current: --";
    scoreInfoLabel.textColor = rgba(210, 255, 225, 0.90);
    scoreInfoLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:11] ?: [UIFont boldSystemFontOfSize:11];
    [panel addSubview:scoreInfoLabel];

    UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(18, 106, 282, 1)];
    divider.backgroundColor = rgba(85, 255, 165, 0.18);
    [panel addSubview:divider];

    UILabel *scoreLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 120, 282, 18)];
    scoreLabel.text = @"SCORE";
    scoreLabel.textColor = rgba(85, 255, 165, 0.78);
    scoreLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:10] ?: [UIFont boldSystemFontOfSize:10];
    [panel addSubview:scoreLabel];

    scoreField = [[UITextField alloc] initWithFrame:CGRectMake(18, 142, 282, 44)];
    scoreField.placeholder = @"Enter score";
    scoreField.text = @"9999";
    scoreField.keyboardType = UIKeyboardTypeNumberPad;
    scoreField.backgroundColor = rgba(17, 24, 21, 0.96);
    scoreField.textColor = rgba(200, 255, 220, 1.0);
    scoreField.layer.cornerRadius = 14;
    scoreField.layer.borderWidth = 1.0;
    scoreField.layer.borderColor = rgba(85, 255, 165, 0.22).CGColor;
    scoreField.clipsToBounds = YES;
    scoreField.font = [UIFont fontWithName:@"Menlo-Bold" size:18] ?: [UIFont boldSystemFontOfSize:18];
    scoreField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 1)];
    scoreField.leftViewMode = UITextFieldViewModeAlways;
    [panel addSubview:scoreField];

    UIButton *preset1K = makeButton(CGRectMake(18, 200, 86, 34),
                                    @"1K",
                                    rgba(30, 62, 47, 0.96),
                                    @selector(setPreset1000));
    [panel addSubview:preset1K];

    UIButton *preset5K = makeButton(CGRectMake(116, 200, 86, 34),
                                    @"5K",
                                    rgba(30, 62, 47, 0.96),
                                    @selector(setPreset5000));
    [panel addSubview:preset5K];

    UIButton *preset10K = makeButton(CGRectMake(214, 200, 86, 34),
                                     @"10K",
                                     rgba(30, 62, 47, 0.96),
                                     @selector(setPreset10000));
    [panel addSubview:preset10K];

    UIButton *saveReloadButton = makeButton(CGRectMake(18, 248, 136, 40),
                                            @"SAVE + RELOAD",
                                            rgba(31, 150, 88, 0.95),
                                            @selector(saveAndReload));
    [panel addSubview:saveReloadButton];

    UIButton *checkButton = makeButton(CGRectMake(164, 248, 136, 40),
                                       @"CHECK",
                                       rgba(37, 92, 178, 0.95),
                                       @selector(checkScoreButton));
    [panel addSubview:checkButton];

    UIButton *resetButton = makeButton(CGRectMake(18, 298, 86, 34),
                                       @"RESET",
                                       rgba(155, 52, 63, 0.95),
                                       @selector(resetScore));
    [panel addSubview:resetButton];

    UIButton *undoButton = makeButton(CGRectMake(116, 298, 86, 34),
                                      @"UNDO",
                                      rgba(179, 105, 28, 0.95),
                                      @selector(undoChange));
    [panel addSubview:undoButton];

    UIButton *hideButton = makeButton(CGRectMake(214, 298, 86, 34),
                                      @"HIDE",
                                      rgba(55, 60, 65, 0.95),
                                      @selector(hideMenu));
    [panel addSubview:hideButton];

    statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 336, 282, 14)];
    statusLabel.text = @"READY";
    statusLabel.textColor = rgba(210, 255, 225, 0.78);
    statusLabel.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    statusLabel.numberOfLines = 1;
    [panel addSubview:statusLabel];

    positionPanelNearMenu();

    debugWindow.hidden = NO;
}

#pragma mark - Constructor

__attribute__((constructor))
static void init_debug_overlay(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        createDebugUI();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            attachScreenDoubleTapGesture();
        });
    });
}