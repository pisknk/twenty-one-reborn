#import "PSListController+Stub.h"
#import "TJLastFmShared.h"
#import "TJPrefsStore.h"
#import <SafariServices/SafariServices.h>
#import <objc/message.h>
#import <signal.h>

extern int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
#ifndef PROC_ALL_PIDS
#define PROC_ALL_PIDS 1
#endif
#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif

static NSString *const kTwentyOneRepoURL = @"https://github.com/pisknk/twenty-one-reborn";
static NSString *const kLegacyStandardPrefsPath = @"/var/mobile/Library/Preferences/com.pisknk.twentyone.plist";
static NSString *const kLegacyRootlessPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.pisknk.twentyone.plist";
static NSString *const kLegacySharedPrefsPath = @"/var/mobile/Media/TwentyOne/com.pisknk.twentyone.plist";

static void killMusicApp(void) {
    pid_t pids[1024];
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    if (bytes > 0) {
        int count = bytes / sizeof(pid_t);
        for (int i = 0; i < count; i++) {
            pid_t pid = pids[i];
            if (pid <= 1) continue;
            char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(pid, pathBuffer, sizeof(pathBuffer)) > 0) {
                NSString *path = [NSString stringWithUTF8String:pathBuffer];
                if ([path containsString:@"/Music.app"] || [path hasSuffix:@"/Music"] || [path containsString:@"MusicApplication"]) {
                    kill(pid, SIGKILL);
                }
            }
        }
    }
}

@interface TJBlacklistEditorController : UIViewController <UITextViewDelegate>
@property (nonatomic, copy) NSString *prefKey;
@property (nonatomic, copy) NSString *itemType;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *instructionsLabel;
- (instancetype)initWithKey:(NSString *)key title:(NSString *)title itemType:(NSString *)itemType;
- (void)setSpecifier:(PSSpecifier *)specifier;
@end

@implementation TJBlacklistEditorController

- (instancetype)initWithKey:(NSString *)key title:(NSString *)title itemType:(NSString *)itemType {
    self = [super init];
    if (self) {
        _prefKey = [key copy];
        _itemType = [itemType copy];
        self.title = title;
    }
    return self;
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *type = [specifier propertyForKey:@"itemType"];
    NSString *lbl = [specifier propertyForKey:@"label"] ?: specifier.name;
    if (key) _prefKey = [key copy];
    if (type) _itemType = [type copy];
    if (lbl) self.title = lbl;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UILabel *instructions = [[UILabel alloc] init];
    instructions.translatesAutoresizingMaskIntoConstraints = NO;
    instructions.numberOfLines = 0;
    instructions.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    instructions.textColor = [UIColor secondaryLabelColor];

    if ([self.itemType isEqualToString:@"album"]) {
        instructions.text = @"To block an album, enter its title below. To enter a new album, press enter to make a new line.";
    } else {
        instructions.text = @"To block an artist, enter their name below. To enter a new artist, press enter to make a new line.";
    }
    [self.view addSubview:instructions];
    self.instructionsLabel = instructions;

    UIView *cardView = [[UIView alloc] init];
    cardView.translatesAutoresizingMaskIntoConstraints = NO;
    cardView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cardView.layer.cornerRadius = 10.0f;
    cardView.layer.cornerCurve = kCACornerCurveContinuous;
    cardView.layer.masksToBounds = YES;
    [self.view addSubview:cardView];

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.backgroundColor = [UIColor clearColor];
    tv.font = [UIFont systemFontOfSize:16.0f];
    tv.textColor = [UIColor labelColor];
    tv.tintColor = [UIColor systemBlueColor];
    tv.autocapitalizationType = UITextAutocapitalizationTypeWords;
    tv.autocorrectionType = UITextAutocorrectionTypeNo;
    tv.spellCheckingType = UITextSpellCheckingTypeNo;
    tv.delegate = self;
    tv.textContainerInset = UIEdgeInsetsMake(12.0f, 10.0f, 12.0f, 10.0f);
    [cardView addSubview:tv];
    self.textView = tv;

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        [instructions.topAnchor constraintEqualToAnchor:guide.topAnchor constant:16.0f],
        [instructions.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:20.0f],
        [instructions.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-20.0f],

        [cardView.topAnchor constraintEqualToAnchor:instructions.bottomAnchor constant:12.0f],
        [cardView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16.0f],
        [cardView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16.0f],

        [tv.topAnchor constraintEqualToAnchor:cardView.topAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor],
    ]];

    if (@available(iOS 15.0, *)) {
        [cardView.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-16.0f].active = YES;
    } else {
        [cardView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-20.0f].active = YES;
    }

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self.textView action:@selector(resignFirstResponder)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];

    [self loadEntries];
}

- (void)loadEntries {
    NSString *raw = prefString(self.prefKey, nil);
    self.textView.text = [tj_blacklistEntries(raw) componentsJoinedByString:@"\n"];
}

- (void)saveEntries {
    NSString *result = [tj_blacklistEntries(self.textView.text) componentsJoinedByString:@"\n"];
    prefSetObject(self.prefKey, result.length > 0 ? result : nil);
}

- (void)textViewDidBeginEditing:(UITextView *)textView {
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:textView action:@selector(resignFirstResponder)];
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    self.navigationItem.rightBarButtonItem = nil;
    [self saveEntries];
}

- (void)textViewDidChange:(UITextView *)textView {
    [self saveEntries];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveEntries];
}

@end

@interface TwentyOnePrefsListController : PSListController <SFSafariViewControllerDelegate> {
    NSString *_currentToken;
}
@end

@implementation TwentyOnePrefsListController

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return [super readPreferenceValue:specifier];
    id val = prefValue(key);
    if (val) return val;
    return [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key) {
        prefSetObject(key, value);
    }
    [super setPreferenceValue:value specifier:specifier];
}

- (void)syncExistingPreferences {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kLegacySharedPrefsPath]) return;
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:kLegacyStandardPrefsPath];
    if (!existing || existing.count == 0) {
        existing = [NSDictionary dictionaryWithContentsOfFile:kLegacyRootlessPrefsPath];
    }
    if (existing && existing.count > 0) {
        for (NSString *key in existing) {
            prefSetObject(key, existing[key]);
        }
    }
}

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    [self syncExistingPreferences];
    [self updateAuthButtonSpecifier];
    return _specifiers;
}

- (void)restartMusicAppAction:(id)sender {
    killMusicApp();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Apple Music Restarted"
                                                                   message:@"The Music app was closed and will reload with all new settings when opened."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateAuthButtonSpecifier];
    if ([self respondsToSelector:@selector(table)]) {
        UITableView *tbl = ((id (*)(id, SEL))objc_msgSend)(self, @selector(table));
        if (tbl && [tbl isKindOfClass:[UITableView class]]) {
            [tbl reloadData];
        }
    }
}

- (void)updateAuthButtonSpecifier {
    NSString *username = prefString(@"lastFmUsername", nil);
    for (PSSpecifier *spec in _specifiers) {
        NSString *specId = nil;
        if ([spec respondsToSelector:@selector(identifier)]) {
            specId = [spec identifier];
        }
        if (!specId && [spec respondsToSelector:@selector(propertyForKey:)]) {
            specId = [spec propertyForKey:@"id"];
        }
        if ([specId isEqualToString:@"lastFmAuthButton"]) {
            if (username && username.length > 0) {
                spec.name = [NSString stringWithFormat:@"Connected as @%@\nTap to Log Out", username];
            } else {
                spec.name = @"Log In with Last.fm";
            }
            break;
        }
    }
}

- (PSSpecifier *)specifierForIndexPathSafe:(NSIndexPath *)indexPath {
    if (!indexPath) return nil;
    if ([self respondsToSelector:@selector(specifierAtIndexPath:)]) {
        return [self specifierAtIndexPath:indexPath];
    }
    if ([self respondsToSelector:@selector(indexForIndexPath:)] && [self respondsToSelector:@selector(specifierAtIndex:)]) {
        NSInteger idx = [self indexForIndexPath:indexPath];
        if (idx >= 0 && idx < self.specifiers.count) {
            return [self specifierAtIndex:idx];
        }
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    if ([super respondsToSelector:@selector(tableView:cellForRowAtIndexPath:)]) {
        cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    }
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"TwentyOneCell"];
    }

    PSSpecifier *spec = [self specifierForIndexPathSafe:indexPath];
    NSString *specId = [spec propertyForKey:@"id"] ?: [spec identifier];

    if ([specId isEqualToString:@"lastFmAuthButton"]) {
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
        cell.textLabel.textAlignment = NSTextAlignmentLeft;

        NSString *username = prefString(@"lastFmUsername", nil);
        if (username && username.length > 0) {
            NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
            style.alignment = NSTextAlignmentLeft;
            style.lineSpacing = 2.0f;
            NSString *fullText = [NSString stringWithFormat:@"Connected as @%@\nTap to Log Out", username];
            NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:fullText
                                                                                      attributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:17.0f weight:UIFontWeightRegular],
                NSForegroundColorAttributeName: [UIColor labelColor],
                NSParagraphStyleAttributeName: style
            }];
            NSRange tapRange = [fullText rangeOfString:@"Tap to Log Out"];
            if (tapRange.location != NSNotFound) {
                [attr addAttributes:@{
                    NSFontAttributeName: [UIFont systemFontOfSize:13.0f weight:UIFontWeightRegular],
                    NSForegroundColorAttributeName: [UIColor secondaryLabelColor]
                } range:tapRange];
            }
            cell.textLabel.attributedText = attr;
        }
    } else if ([specId isEqualToString:@"blacklistArtistsLink"]) {
        NSUInteger count = tj_blacklistEntries(prefString(@"lastFmBlacklistedArtists", nil)).count;
        cell.detailTextLabel.text = count > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : @"";
    } else if ([specId isEqualToString:@"blacklistAlbumsLink"]) {
        NSUInteger count = tj_blacklistEntries(prefString(@"lastFmBlacklistedAlbums", nil)).count;
        cell.detailTextLabel.text = count > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : @"";
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierForIndexPathSafe:indexPath];
    NSString *specId = [spec propertyForKey:@"id"] ?: [spec identifier];
    if ([specId isEqualToString:@"lastFmAuthButton"]) {
        NSString *username = prefString(@"lastFmUsername", nil);
        if (username && username.length > 0) {
            return 60.0f;
        }
    }
    if ([super respondsToSelector:@selector(tableView:heightForRowAtIndexPath:)]) {
        return [super tableView:tableView heightForRowAtIndexPath:indexPath];
    }
    return 44.0f;
}

- (void)openArtistsBlacklist:(id)sender {
    (void)sender;
    TJBlacklistEditorController *vc = [[TJBlacklistEditorController alloc] initWithKey:@"lastFmBlacklistedArtists" title:@"Artists" itemType:@"artist"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openAlbumsBlacklist:(id)sender {
    (void)sender;
    TJBlacklistEditorController *vc = [[TJBlacklistEditorController alloc] initWithKey:@"lastFmBlacklistedAlbums" title:@"Albums" itemType:@"album"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierForIndexPathSafe:indexPath];
    NSString *specId = [spec propertyForKey:@"id"] ?: [spec identifier];

    if ([specId isEqualToString:@"blacklistArtistsLink"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self openArtistsBlacklist:nil];
        return;
    }

    if ([specId isEqualToString:@"blacklistAlbumsLink"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self openAlbumsBlacklist:nil];
        return;
    }

    if ([super respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        [super tableView:tableView didSelectRowAtIndexPath:indexPath];
    }
}

- (void)openRepo:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:kTwentyOneRepoURL];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)lastFmAuthAction:(id)sender {
    (void)sender;
    NSString *username = prefString(@"lastFmUsername", nil);

    if (username && username.length > 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Last.fm"
                                                                       message:[NSString stringWithFormat:@"Currently connected as @%@. Do you want to disconnect?", username]
                                                                preferredStyle:UIAlertControllerStyleActionSheet];

        [alert addAction:[UIAlertAction actionWithTitle:@"Log Out"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            prefSetObject(@"lastFmSessionKey", nil);
            prefSetObject(@"lastFmUsername", nil);
            [self reloadSpecifiers];
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];

        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSString *urlStr = [NSString stringWithFormat:@"https://ws.audioscrobbler.com/2.0/?method=auth.getToken&api_key=%@&format=json", kTJLastFmAPIKey];
    NSURL *url = [NSURL URLWithString:urlStr];
    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];

    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Connection Error"
                                                                                  message:@"Could not connect to Last.fm servers."
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errAlert animated:YES completion:nil];
            });
            return;
        }

        @try {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *token = json[@"token"];
            if (token && token.length > 0) {
                self->_currentToken = [token copy];
                NSString *authWebURLStr = [NSString stringWithFormat:@"https://www.last.fm/api/auth/?api_key=%@&token=%@", kTJLastFmAPIKey, token];
                NSURL *authWebURL = [NSURL URLWithString:authWebURLStr];
                dispatch_async(dispatch_get_main_queue(), ^{
                    SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:authWebURL];
                    safari.delegate = self;
                    [self presentViewController:safari animated:YES completion:nil];
                });
                return;
            }
        } @catch (__unused id e) {}

        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Authentication Error"
                                                                              message:@"Invalid response from Last.fm."
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:errAlert animated:YES completion:nil];
        });
    }] resume];
}

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    if (!_currentToken) return;
    NSString *token = [_currentToken copy];
    _currentToken = nil;

    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
    params[@"method"] = @"auth.getSession";
    params[@"api_key"] = kTJLastFmAPIKey;
    params[@"token"] = token;
    NSString *sig = tj_lastfm_signature(params, kTJLastFmAPISecret);

    NSString *urlStr = [NSString stringWithFormat:@"https://ws.audioscrobbler.com/2.0/?method=auth.getSession&api_key=%@&token=%@&api_sig=%@&format=json", kTJLastFmAPIKey, token, sig];
    NSURL *url = [NSURL URLWithString:urlStr];
    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];

    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        __block BOOL handled = NO;
        if (!err && data) {
            @try {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                NSDictionary *session = json[@"session"];
                NSString *sk = session[@"key"];
                NSString *name = session[@"name"];
                if (sk.length > 0 && name.length > 0) {
                    handled = YES;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        prefSetObject(@"lastFmSessionKey", sk);
                        prefSetObject(@"lastFmUsername", name);
                        [self reloadSpecifiers];

                        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Last.fm Connected"
                                                                                              message:[NSString stringWithFormat:@"Successfully logged in as @%@!", name]
                                                                                       preferredStyle:UIAlertControllerStyleAlert];
                        [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                        [self presentViewController:successAlert animated:YES completion:nil];
                    });
                }
            } @catch (__unused id e) {}
        }
        if (!handled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Authentication Error"
                                                                                  message:@"Could not complete Last.fm login. Please try again."
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errAlert animated:YES completion:nil];
            });
        }
    }] resume];
}

- (void)flushOfflineQueueAction:(id)sender {
    (void)sender;
    NSArray *queue = [NSArray arrayWithContentsOfFile:kTJOfflineQueueFile];
    NSUInteger count = queue ? queue.count : 0;

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kTJFlushQueueDarwinNotification,
                                         NULL, NULL, YES);

    NSString *msg = (count > 0) ? [NSString stringWithFormat:@"Asked the scrobbler to submit %lu pending scrobble(s) now.", (unsigned long)count] : @"There are no pending offline scrobbles.";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Offline Scrobbles"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
