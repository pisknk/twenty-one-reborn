#import <UIKit/UIKit.h>

@interface PSSpecifier : NSObject
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *identifier;
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
@end

@interface PSListController : UIViewController <UITableViewDelegate, UITableViewDataSource> {
	NSMutableArray *_specifiers;
}
@property (nonatomic, retain) NSMutableArray *specifiers;
- (UITableView *)table;
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)plistName target:(id)target;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)reloadSpecifiers;
- (PSSpecifier *)specifierForID:(NSString *)identifier;
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
- (PSSpecifier *)specifierAtIndex:(NSInteger)index;
- (NSInteger)indexForIndexPath:(NSIndexPath *)indexPath;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
@end
