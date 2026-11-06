#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const AIEVersion = @"1.2.2";
static const NSInteger AIEWindowTag = 0x41494532;

@interface AIEWindow : UIWindow
@end
@implementation AIEWindow
@end

@interface AIEController : NSObject <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) AIEWindow *overlay;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UICollectionView *grid;
@property (nonatomic, strong) NSMutableArray<UIImage *> *images;
@property (nonatomic, strong) NSMutableSet<NSString *> *hashes;
@property (nonatomic, assign) BOOL panelOpen;
+ (instancetype)shared;
- (void)install;
@end

@implementation AIEController

+ (instancetype)shared {
    static AIEController *obj;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ obj = [AIEController new]; });
    return obj;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _images = [NSMutableArray array];
        _hashes = [NSMutableSet set];
    }
    return self;
}

- (void)install {
    if (self.overlay) { return; }
    UIWindowScene *scene = [self activeScene];
    if (scene) {
        self.overlay = [[AIEWindow alloc] initWithWindowScene:scene];
    } else {
        self.overlay = [[AIEWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }
    self.overlay.windowLevel = UIWindowLevelAlert + 10;
    self.overlay.backgroundColor = UIColor.clearColor;
    self.overlay.tag = AIEWindowTag;
    self.overlay.hidden = NO;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    self.overlay.rootViewController = root;
    [self.overlay makeKeyAndVisible];
    [[self appKeyWindow] makeKeyWindow];
    [self addFabTo:root.view];
}

- (UIWindowScene *)activeScene {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) { continue; }
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

- (UIWindow *)appKeyWindow {
    UIWindowScene *scene = [self activeScene];
    if (scene) {
        for (UIWindow *window in scene.windows) {
            if (window.tag == AIEWindowTag) { continue; }
            if (window.isKeyWindow) { return window; }
        }
        for (UIWindow *window in scene.windows) {
            if (window.tag == AIEWindowTag) { continue; }
            if (!window.hidden) { return window; }
        }
    }
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.tag == AIEWindowTag) { continue; }
        if (window.isKeyWindow) { return window; }
    }
    return nil;
}

- (void)addFabTo:(UIView *)host {
    UIButton *fab = [UIButton buttonWithType:UIButtonTypeSystem];
    fab.translatesAutoresizingMaskIntoConstraints = NO;
    [fab setTitle:@"图" forState:UIControlStateNormal];
    fab.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    [fab setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    fab.backgroundColor = [UIColor colorWithRed:0.20 green:0.48 blue:1.0 alpha:0.92];
    fab.layer.cornerRadius = 22;
    fab.layer.shadowColor = UIColor.blackColor.CGColor;
    fab.layer.shadowOpacity = 0.25;
    fab.layer.shadowRadius = 8;
    fab.layer.shadowOffset = CGSizeMake(0, 4);
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:fab];
    UILayoutGuide *safe = host.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [fab.widthAnchor constraintEqualToConstant:44],
        [fab.heightAnchor constraintEqualToConstant:44],
        [fab.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [fab.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-88]
    ]];
}

- (void)togglePanel {
    if (self.panelOpen) {
        [self hidePanel];
    } else {
        [self showPanel];
    }
}

- (void)showPanel {
    UIView *host = self.overlay.rootViewController.view;
    if (!self.panel) {
        [self buildPanelIn:host];
    }
    self.panelOpen = YES;
    self.panel.hidden = NO;
    [self.overlay makeKeyAndVisible];
    [UIView animateWithDuration:0.2 animations:^{
        self.panel.alpha = 1;
        self.panel.transform = CGAffineTransformIdentity;
    }];
}

- (void)hidePanel {
    self.panelOpen = NO;
    [UIView animateWithDuration:0.18 animations:^{
        self.panel.alpha = 0;
        self.panel.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:^(BOOL finished) {
        self.panel.hidden = YES;
        [[self appKeyWindow] makeKeyWindow];
    }];
}

- (void)buildPanelIn:(UIView *)host {
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 18;
    card.clipsToBounds = YES;
    card.alpha = 0;
    card.transform = CGAffineTransformMakeScale(0.96, 0.96);
    self.panel = card;
    [host addSubview:card];
    UILayoutGuide *safe = host.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-16],
        [card.topAnchor constraintEqualToAnchor:safe.topAnchor constant:56],
        [card.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-72]
    ]];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = [NSString stringWithFormat:@"图标提取 %@", AIEVersion];
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [card.contentView addSubview:title];

    self.countLabel = [UILabel new];
    self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.countLabel.text = @"当前页 0 个";
    self.countLabel.font = [UIFont systemFontOfSize:13];
    self.countLabel.textColor = UIColor.secondaryLabelColor;
    [card.contentView addSubview:self.countLabel];

    UIButton *scan = [self pillButton:@"图" color:[UIColor colorWithRed:0.20 green:0.48 blue:1.0 alpha:1]];
    [scan addTarget:self action:@selector(scanCurrentPage) forControlEvents:UIControlEventTouchUpInside];
    UIButton *clear = [self pillButton:@"清空" color:[UIColor colorWithWhite:0.45 alpha:1]];
    [clear addTarget:self action:@selector(clearImages) forControlEvents:UIControlEventTouchUpInside];
    UIButton *share = [self pillButton:@"导出" color:[UIColor colorWithRed:0.20 green:0.70 blue:0.40 alpha:1]];
    [share addTarget:self action:@selector(exportAll) forControlEvents:UIControlEventTouchUpInside];
    UIButton *close = [self pillButton:@"关闭" color:[UIColor colorWithRed:0.90 green:0.30 blue:0.30 alpha:1]];
    [close addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[scan, clear, share, close]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 8;
    actions.distribution = UIStackViewDistributionFillEqually;
    [card.contentView addSubview:actions];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(8, 8, 8, 8);
    self.grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.grid.translatesAutoresizingMaskIntoConstraints = NO;
    self.grid.backgroundColor = UIColor.clearColor;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    [self.grid registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"cell"];
    [card.contentView addSubview:self.grid];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:16],
        [self.countLabel.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [self.countLabel.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-16],
        [actions.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [actions.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:16],
        [actions.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-16],
        [actions.heightAnchor constraintEqualToConstant:36],
        [self.grid.topAnchor constraintEqualToAnchor:actions.bottomAnchor constant:12],
        [self.grid.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
        [self.grid.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor],
        [self.grid.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor]
    ]];
}

- (UIButton *)pillButton:(NSString *)title color:(UIColor *)color {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    button.backgroundColor = color;
    button.layer.cornerRadius = 8;
    return button;
}

- (void)scanCurrentPage {
    [self.images removeAllObjects];
    [self.hashes removeAllObjects];
    UIWindow *window = [self appKeyWindow];
    if (window) {
        [self walk:window];
    }
    self.countLabel.text = [NSString stringWithFormat:@"当前页 %lu 个", (unsigned long)self.images.count];
    [self.grid reloadData];
}

- (void)clearImages {
    [self.images removeAllObjects];
    [self.hashes removeAllObjects];
    self.countLabel.text = @"当前页 0 个";
    [self.grid reloadData];
}

- (void)walk:(UIView *)view {
    if (view.hidden || view.alpha < 0.01) { return; }
    if ([view.window isKindOfClass:AIEWindow.class] || view.window.tag == AIEWindowTag) { return; }
    if ([view isKindOfClass:UIImageView.class]) {
        UIImageView *imageView = (UIImageView *)view;
        [self collect:imageView.image];
        [self collect:imageView.highlightedImage];
        for (UIImage *frame in imageView.animationImages) {
            [self collect:frame];
        }
    } else if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        UIControlState states[4] = {
            UIControlStateNormal, UIControlStateHighlighted, UIControlStateSelected, UIControlStateDisabled
        };
        for (int i = 0; i < 4; i++) {
            [self collect:[button imageForState:states[i]]];
            [self collect:[button backgroundImageForState:states[i]]];
        }
        [self collect:button.currentImage];
        [self collect:button.currentBackgroundImage];
    }
    for (UIView *child in view.subviews) {
        [self walk:child];
    }
}

- (void)collect:(UIImage *)image {
    if (!image || image.size.width < 1 || image.size.height < 1) { return; }
    NSString *digest = [self hashForImage:image];
    if (!digest || [self.hashes containsObject:digest]) { return; }
    [self.hashes addObject:digest];
    [self.images addObject:image];
}

- (NSString *)hashForImage:(UIImage *)image {
    CGSize size = image.size;
    NSString *seed = [NSString stringWithFormat:@"%.1f-%.1f-%ld-%p", size.width, size.height, (long)image.scale, image.CGImage];
    NSData *png = UIImagePNGRepresentation(image);
    NSData *payload = png.length > 0 ? png : [seed dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char md[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(payload.bytes, (CC_LONG)payload.length, md);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [out appendFormat:@"%02x", md[i]];
    }
    return out;
}

- (void)exportAll {
    if (self.images.count == 0) { return; }
    NSMutableArray *items = [NSMutableArray array];
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"AppleIconExtractor"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSInteger index = 0;
    for (UIImage *image in self.images) {
        NSData *data = UIImagePNGRepresentation(image);
        if (!data) { continue; }
        NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"icon_%03ld.png", (long)index]];
        [data writeToFile:path atomically:YES];
        NSURL *url = [NSURL fileURLWithPath:path];
        if (url) { [items addObject:url]; }
        index += 1;
    }
    if (items.count == 0) { return; }
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    UIViewController *root = self.overlay.rootViewController;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = root.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(root.view.bounds.size.width / 2, 80, 1, 1);
    }
    [root presentViewController:sheet animated:YES completion:nil];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.images.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:indexPath];
    UIImageView *thumb = [cell.contentView viewWithTag:88];
    if (!thumb) {
        thumb = [[UIImageView alloc] initWithFrame:cell.contentView.bounds];
        thumb.tag = 88;
        thumb.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        thumb.contentMode = UIViewContentModeScaleAspectFit;
        thumb.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1];
        thumb.layer.cornerRadius = 8;
        thumb.clipsToBounds = YES;
        [cell.contentView addSubview:thumb];
    }
    thumb.image = self.images[indexPath.item];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = floor((collectionView.bounds.size.width - 40) / 4.0);
    if (width < 56) { width = 56; }
    return CGSizeMake(width, width);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    UIImage *image = self.images[indexPath.item];
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[image] applicationActivities:nil];
    UIViewController *root = self.overlay.rootViewController;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = collectionView;
        sheet.popoverPresentationController.sourceRect = [collectionView layoutAttributesForItemAtIndexPath:indexPath].frame;
    }
    [root presentViewController:sheet animated:YES completion:nil];
}

@end

__attribute__((constructor))
static void AppleIconExtractorInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^install)(void) = ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[AIEController shared] install];
            });
        };
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
            install();
        } else {
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                              object:nil
                                                               queue:NSOperationQueue.mainQueue
                                                          usingBlock:^(__unused NSNotification *note) {
                install();
            }];
        }
    });
}
