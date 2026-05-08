#import <Cocoa/Cocoa.h>

static NSString *ToolPath(void) {
    NSString *path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"keychain_secrets.py"];
    return path;
}

static NSString *RunTool(NSArray<NSString *> *arguments, NSString *stdinText, int *status) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = ToolPath();
    task.arguments = arguments;

    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;
    if (stdinText != nil) {
        NSPipe *stdinPipe = [NSPipe pipe];
        task.standardInput = stdinPipe;
        [task launch];
        NSData *data = [stdinText dataUsingEncoding:NSUTF8StringEncoding];
        [[stdinPipe fileHandleForWriting] writeData:data];
        [[stdinPipe fileHandleForWriting] closeFile];
    } else {
        [task launch];
    }
    [task waitUntilExit];

    if (status != NULL) {
        *status = task.terminationStatus;
    }
    NSData *outData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
    NSData *errData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
    NSString *out = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *err = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"";
    if (task.terminationStatus != 0 && err.length > 0) {
        return err;
    }
    return out;
}

static NSString *RunSecurity(NSArray<NSString *> *arguments, int *status) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/security";
    task.arguments = arguments;

    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;
    [task launch];
    [task waitUntilExit];

    if (status != NULL) {
        *status = task.terminationStatus;
    }
    NSData *outData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
    NSData *errData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
    NSString *out = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *err = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"";
    if (task.terminationStatus != 0 && err.length > 0) {
        return err;
    }
    return out;
}

static NSString *DefaultKeychainPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Keychains/login.keychain-db"];
}

static NSString *IndexPath(void) {
    const char *overridePath = getenv("KEYCHAIN_SECRETS_INDEX_PATH");
    if (overridePath != NULL && strlen(overridePath) > 0) {
        return [NSString stringWithUTF8String:overridePath];
    }
    return [NSHomeDirectory() stringByAppendingPathComponent:@".codex/keychain-secrets/index.json"];
}

static BOOL UsesIndexOverride(void) {
    const char *overridePath = getenv("KEYCHAIN_SECRETS_INDEX_PATH");
    return overridePath != NULL && strlen(overridePath) > 0;
}

static NSScreen *PreferredScreen(void) {
    NSPoint primaryPoint = NSMakePoint(100, 100);
    for (NSScreen *screen in NSScreen.screens) {
        if (NSPointInRect(primaryPoint, screen.frame)) {
            return screen;
        }
    }
    return NSScreen.mainScreen ?: NSScreen.screens.firstObject;
}

static NSString *Trim(NSString *value) {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSMenu *TextEditingMenu(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [menu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@""];
    return menu;
}

static void InstallMainMenu(void) {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main Menu"];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appMenuItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"KeychainSecrets"];
    [appMenu addItemWithTitle:@"Quit KeychainSecrets" action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;

    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editMenuItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editMenuItem.submenu = editMenu;

    NSApp.mainMenu = mainMenu;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property NSWindow *window;
@property NSTableView *table;
@property NSMutableArray<NSString *> *names;
@property NSDictionary<NSString *, NSDictionary *> *metadata;
@property NSTextField *nameField;
@property NSTextField *envField;
@property NSTextField *serviceField;
@property NSTextField *accountField;
@property NSSecureTextField *secretField;
@property NSTextField *secretVisibleField;
@property NSButton *secretToggleButton;
@property NSButton *secretCopyButton;
@property NSTextView *noteView;
@property NSTextField *statusLabel;
@property NSTextField *hintLabel;
@property NSString *keychainPath;
@property BOOL secretVisible;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.names = [NSMutableArray array];
    [self buildUI];
    [self refresh:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)buildUI {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1180, 680)
                                             styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"KeychainSecrets";
    NSScreen *screen = PreferredScreen();
    if (screen != nil) {
        NSRect visibleFrame = screen.visibleFrame;
        NSRect frame = self.window.frame;
        frame.origin.x = NSMidX(visibleFrame) - NSWidth(frame) / 2;
        frame.origin.y = NSMidY(visibleFrame) - NSHeight(frame) / 2;
        [self.window setFrame:frame display:NO];
    }

    NSStackView *root = [NSStackView stackViewWithViews:@[]];
    root.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    root.spacing = 18;
    root.edgeInsets = NSEdgeInsetsMake(16, 18, 18, 18);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor],
    ]];

    self.table = [[NSTableView alloc] init];
    self.table.delegate = self;
    self.table.dataSource = self;
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.allowsEmptySelection = YES;
    self.table.rowHeight = 24;
    self.table.intercellSpacing = NSMakeSize(0, 2);
    self.table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    [self addColumn:@"name" title:@"Name" width:210];
    [self addColumn:@"env" title:@"Env" width:180];
    [self addColumn:@"note" title:@"Note" width:220];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.documentView = self.table;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll.widthAnchor constraintGreaterThanOrEqualToConstant:560].active = YES;
    [root addArrangedSubview:scroll];

    NSView *form = [[NSView alloc] init];
    form.translatesAutoresizingMaskIntoConstraints = NO;
    [form.widthAnchor constraintGreaterThanOrEqualToConstant:544].active = YES;

    NSView *header = [[NSView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [form addSubview:header];

    NSTextField *title = [NSTextField labelWithString:@"Secret Configuration"];
    title.font = [NSFont boldSystemFontOfSize:18];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:title];

    NSButton *newButton = [self button:@"New" action:@selector(newEntry:)];
    NSButton *saveButton = [self button:@"Save" action:@selector(save:)];
    NSButton *deleteButton = [self button:@"Delete" action:@selector(deleteEntry:)];
    NSButton *refreshButton = [self button:@"Refresh" action:@selector(refresh:)];
    NSArray<NSButton *> *buttonViews = @[newButton, saveButton, deleteButton, refreshButton];
    for (NSButton *button in buttonViews) {
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [header addSubview:button];
    }

    self.nameField = [NSTextField textFieldWithString:@""];
    self.envField = [NSTextField textFieldWithString:@""];
    self.serviceField = [NSTextField textFieldWithString:@""];
    self.accountField = [NSTextField textFieldWithString:NSUserName()];
    self.secretField = [NSSecureTextField textFieldWithString:@""];
    self.secretField.placeholderString = @"Leave blank to keep existing secret";
    self.secretVisibleField = [NSTextField textFieldWithString:@""];
    self.secretVisibleField.placeholderString = @"Leave blank to keep existing secret";
    self.secretVisibleField.hidden = YES;
    self.secretToggleButton = [self button:@"Show" action:@selector(toggleSecret:)];
    self.secretCopyButton = [self button:@"Copy" action:@selector(copySecret:)];
    for (NSView *view in @[self.nameField, self.envField, self.serviceField, self.accountField, self.secretField, self.secretVisibleField]) {
        view.menu = TextEditingMenu();
    }
    self.noteView = [[NSTextView alloc] init];
    self.noteView.font = [NSFont systemFontOfSize:13];
    self.noteView.menu = TextEditingMenu();

    NSStackView *fields = [NSStackView stackViewWithViews:@[
        [self row:@"Name" field:self.nameField],
        [self row:@"Environment variable" field:self.envField],
        [self row:@"Keychain service" field:self.serviceField],
        [self row:@"Keychain account" field:self.accountField],
        [self secretRow],
    ]];
    fields.orientation = NSUserInterfaceLayoutOrientationVertical;
    fields.alignment = NSLayoutAttributeLeading;
    fields.spacing = 10;
    fields.translatesAutoresizingMaskIntoConstraints = NO;
    [form addSubview:fields];

    NSScrollView *noteScroll = [[NSScrollView alloc] init];
    noteScroll.hasVerticalScroller = YES;
    noteScroll.borderType = NSBezelBorder;
    noteScroll.documentView = self.noteView;
    noteScroll.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *noteLabel = [NSTextField labelWithString:@"Note"];
    noteLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    noteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [form addSubview:noteLabel];
    [form addSubview:noteScroll];

    self.hintLabel = [NSTextField wrappingLabelWithString:@"Secret values are stored in macOS Keychain. This app stores only metadata in ~/.codex/keychain-secrets/index.json."];
    self.hintLabel.textColor = NSColor.secondaryLabelColor;
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [form addSubview:self.hintLabel];

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [form addSubview:self.statusLabel];

    CGFloat panelPadding = 8;
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:form.leadingAnchor constant:panelPadding],
        [header.trailingAnchor constraintEqualToAnchor:form.trailingAnchor constant:-panelPadding],
        [header.topAnchor constraintEqualToAnchor:form.topAnchor constant:2],
        [header.heightAnchor constraintEqualToConstant:34],

        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:newButton.leadingAnchor constant:-14],

        [refreshButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [refreshButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [deleteButton.trailingAnchor constraintEqualToAnchor:refreshButton.leadingAnchor constant:-8],
        [deleteButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [saveButton.trailingAnchor constraintEqualToAnchor:deleteButton.leadingAnchor constant:-8],
        [saveButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [newButton.trailingAnchor constraintEqualToAnchor:saveButton.leadingAnchor constant:-8],
        [newButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [fields.leadingAnchor constraintEqualToAnchor:form.leadingAnchor constant:panelPadding],
        [fields.trailingAnchor constraintEqualToAnchor:form.trailingAnchor constant:-panelPadding],
        [fields.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:18],

        [noteLabel.leadingAnchor constraintEqualToAnchor:form.leadingAnchor constant:panelPadding],
        [noteLabel.topAnchor constraintEqualToAnchor:fields.bottomAnchor constant:14],
        [noteLabel.trailingAnchor constraintEqualToAnchor:form.trailingAnchor constant:-panelPadding],

        [noteScroll.leadingAnchor constraintEqualToAnchor:form.leadingAnchor constant:panelPadding],
        [noteScroll.trailingAnchor constraintEqualToAnchor:form.trailingAnchor constant:-panelPadding],
        [noteScroll.topAnchor constraintEqualToAnchor:noteLabel.bottomAnchor constant:4],
        [noteScroll.heightAnchor constraintEqualToConstant:130],

        [self.hintLabel.leadingAnchor constraintEqualToAnchor:form.leadingAnchor constant:panelPadding],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:form.trailingAnchor constant:-panelPadding],
        [self.hintLabel.topAnchor constraintEqualToAnchor:noteScroll.bottomAnchor constant:16],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:form.leadingAnchor constant:panelPadding],
        [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:form.trailingAnchor constant:-panelPadding],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.hintLabel.bottomAnchor constant:10],
    ]];
    [root addArrangedSubview:form];
    [self newEntry:nil];
}

- (void)addColumn:(NSString *)identifier title:(NSString *)title width:(CGFloat)width {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.width = width;
    [self.table addTableColumn:column];
}

- (NSView *)row:(NSString *)label field:(NSTextField *)field {
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *labelView = [NSTextField labelWithString:label];
    labelView.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    labelView.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholderString = label;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:labelView];
    [row addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:34],
        [labelView.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [labelView.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [labelView.widthAnchor constraintEqualToConstant:142],
        [field.leadingAnchor constraintEqualToAnchor:labelView.trailingAnchor constant:12],
        [field.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [field.widthAnchor constraintEqualToConstant:390],
    ]];
    return row;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

- (NSView *)secretRow {
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *labelView = [NSTextField labelWithString:@"Secret value"];
    labelView.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    labelView.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:labelView];

    NSView *inputRow = [[NSView alloc] init];
    inputRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.secretField.translatesAutoresizingMaskIntoConstraints = NO;
    self.secretVisibleField.translatesAutoresizingMaskIntoConstraints = NO;
    self.secretToggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.secretCopyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [inputRow addSubview:self.secretField];
    [inputRow addSubview:self.secretVisibleField];
    [inputRow addSubview:self.secretToggleButton];
    [inputRow addSubview:self.secretCopyButton];
    [row addSubview:inputRow];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:34],
        [labelView.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [labelView.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [labelView.widthAnchor constraintEqualToConstant:142],
        [inputRow.leadingAnchor constraintEqualToAnchor:labelView.trailingAnchor constant:12],
        [inputRow.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [inputRow.widthAnchor constraintEqualToConstant:390],
        [inputRow.heightAnchor constraintEqualToConstant:30],
        [self.secretToggleButton.trailingAnchor constraintEqualToAnchor:inputRow.trailingAnchor],
        [self.secretToggleButton.centerYAnchor constraintEqualToAnchor:inputRow.centerYAnchor],
        [self.secretToggleButton.widthAnchor constraintEqualToConstant:72],
        [self.secretCopyButton.trailingAnchor constraintEqualToAnchor:self.secretToggleButton.leadingAnchor constant:-8],
        [self.secretCopyButton.centerYAnchor constraintEqualToAnchor:inputRow.centerYAnchor],
        [self.secretCopyButton.widthAnchor constraintEqualToConstant:72],

        [self.secretField.leadingAnchor constraintEqualToAnchor:inputRow.leadingAnchor],
        [self.secretField.trailingAnchor constraintEqualToAnchor:self.secretCopyButton.leadingAnchor constant:-8],
        [self.secretField.centerYAnchor constraintEqualToAnchor:inputRow.centerYAnchor],

        [self.secretVisibleField.leadingAnchor constraintEqualToAnchor:inputRow.leadingAnchor],
        [self.secretVisibleField.trailingAnchor constraintEqualToAnchor:self.secretCopyButton.leadingAnchor constant:-8],
        [self.secretVisibleField.centerYAnchor constraintEqualToAnchor:inputRow.centerYAnchor],
    ]];
    return row;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.names.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *name = self.names[row];
    NSString *identifier = tableColumn.identifier;
    NSString *value = name;
    if ([identifier isEqualToString:@"env"]) {
        value = [self field:@"env" forName:name fallback:name];
    } else if ([identifier isEqualToString:@"note"]) {
        value = [self field:@"note" forName:name fallback:@""];
    }
    NSTableCellView *cell = [[NSTableCellView alloc] init];
    NSTextField *text = [NSTextField labelWithString:value ?: @""];
    text.font = [NSFont systemFontOfSize:13];
    text.lineBreakMode = NSLineBreakByTruncatingTail;
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:text];
    [NSLayoutConstraint activateConstraints:@[
        [text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6],
        [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-6],
        [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= self.names.count) {
        return;
    }
    [self loadEntry:self.names[row]];
}

- (void)loadMetadata {
    NSData *data = [NSData dataWithContentsOfFile:IndexPath()];
    if (data == nil) {
        self.metadata = @{};
        return;
    }

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        self.metadata = @{};
        return;
    }

    NSMutableDictionary<NSString *, NSDictionary *> *metadata = [NSMutableDictionary dictionary];
    NSDictionary *rawMetadata = (NSDictionary *)object;
    for (id key in rawMetadata) {
        id value = rawMetadata[key];
        if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSDictionary class]]) {
            metadata[key] = value;
        }
    }
    self.metadata = metadata;
}

- (NSString *)field:(NSString *)field forName:(NSString *)name fallback:(NSString *)fallback {
    id value = self.metadata[name][field];
    if (![value isKindOfClass:[NSString class]]) {
        return fallback;
    }
    NSString *trimmed = Trim(value);
    return trimmed.length > 0 ? trimmed : fallback;
}

- (void)loadEntry:(NSString *)name {
    self.nameField.stringValue = name;
    self.nameField.editable = NO;
    self.envField.stringValue = [self field:@"env" forName:name fallback:name];
    self.serviceField.stringValue = [self field:@"service" forName:name fallback:name];
    self.accountField.stringValue = [self field:@"account" forName:name fallback:NSUserName()];
    self.keychainPath = [self field:@"keychain" forName:name fallback:DefaultKeychainPath()];
    [self resetSecretFields];
    self.noteView.string = [self field:@"note" forName:name fallback:@""];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Loaded %@", name];
}

- (IBAction)newEntry:(id)sender {
    [self.table deselectAll:nil];
    self.nameField.editable = YES;
    self.nameField.stringValue = @"";
    self.envField.stringValue = @"";
    self.serviceField.stringValue = @"";
    self.accountField.stringValue = NSUserName();
    self.keychainPath = DefaultKeychainPath();
    [self resetSecretFields];
    self.noteView.string = @"";
    self.statusLabel.stringValue = @"New entry";
}

- (IBAction)refresh:(id)sender {
    NSString *selectedName = Trim(self.nameField.stringValue);
    [self loadMetadata];
    [self.names removeAllObjects];
    NSArray<NSString *> *sortedNames = [self.metadata.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [self.names addObjectsFromArray:sortedNames];
    [self.table reloadData];
    NSClipView *clipView = self.table.enclosingScrollView.contentView;
    [clipView scrollToPoint:NSMakePoint(0, clipView.bounds.origin.y)];
    [self.table.enclosingScrollView reflectScrolledClipView:clipView];
    if (selectedName.length > 0) {
        NSUInteger index = [self.names indexOfObject:selectedName];
        if (index != NSNotFound) {
            [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        }
    } else if (UsesIndexOverride() && self.names.count > 0) {
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
    self.statusLabel.stringValue = @"Refreshed";
}

- (IBAction)save:(id)sender {
    NSString *name = Trim(self.nameField.stringValue);
    if (name.length == 0) {
        [self showError:@"Name is required."];
        return;
    }
    NSString *envName = Trim(self.envField.stringValue);
    NSString *service = Trim(self.serviceField.stringValue);
    NSString *account = Trim(self.accountField.stringValue);
    NSString *secret = self.secretVisible ? self.secretVisibleField.stringValue : self.secretField.stringValue;
    NSString *note = self.noteView.string ?: @"";
    if (envName.length == 0) envName = name;
    if (service.length == 0) service = name;
    if (account.length == 0) account = NSUserName();

    int status = 0;
    NSString *output = nil;
    if (secret.length > 0) {
        output = RunTool(@[@"put", name, @"--stdin", @"--env", envName, @"--service", service, @"--account", account, @"--note", note], secret, &status);
    } else {
        output = RunTool(@[@"update", name, @"--env", envName, @"--service", service, @"--account", account, @"--note", note], nil, &status);
    }
    if (status != 0) {
        [self showError:output];
        return;
    }
    self.nameField.editable = NO;
    [self resetSecretFields];
    [self refresh:nil];
    NSUInteger index = [self.names indexOfObject:name];
    if (index != NSNotFound) {
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    }
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Saved %@", name];
}

- (IBAction)deleteEntry:(id)sender {
    NSString *name = Trim(self.nameField.stringValue);
    if (name.length == 0) {
        [self showError:@"Select an entry to delete."];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete %@?", name];
    alert.informativeText = @"This removes the Keychain item and metadata.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    int status = 0;
    NSString *output = RunTool(@[@"delete", name], nil, &status);
    if (status != 0) {
        [self showError:output];
        return;
    }
    [self refresh:nil];
    [self newEntry:nil];
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Keychain Secrets";
    alert.informativeText = message ?: @"Unknown error";
    [alert runModal];
    self.statusLabel.stringValue = message ?: @"Unknown error";
}

- (void)resetSecretFields {
    self.secretVisible = NO;
    self.secretField.hidden = NO;
    self.secretVisibleField.hidden = YES;
    self.secretField.stringValue = @"";
    self.secretVisibleField.stringValue = @"";
    self.secretToggleButton.title = @"Show";
}

- (NSString *)currentSecretValue {
    NSString *typedSecret = self.secretVisible ? self.secretVisibleField.stringValue : self.secretField.stringValue;
    if (typedSecret.length > 0) {
        return typedSecret;
    }

    NSString *name = Trim(self.nameField.stringValue);
    if (name.length == 0 || self.nameField.editable) {
        return @"";
    }

    int status = 0;
    NSString *service = Trim(self.serviceField.stringValue);
    NSString *account = Trim(self.accountField.stringValue);
    NSString *keychain = self.keychainPath.length > 0 ? self.keychainPath : DefaultKeychainPath();
    if (service.length == 0) service = name;
    if (account.length == 0) account = NSUserName();
    NSString *output = RunSecurity(@[@"find-generic-password", @"-a", account, @"-s", service, @"-w", keychain], &status);
    if (status != 0) {
        [self showError:output];
        return nil;
    }
    return Trim(output);
}

- (IBAction)toggleSecret:(id)sender {
    if (self.secretVisible) {
        self.secretField.stringValue = self.secretVisibleField.stringValue;
        self.secretVisibleField.hidden = YES;
        self.secretField.hidden = NO;
        self.secretVisible = NO;
        self.secretToggleButton.title = @"Show";
        return;
    }

    NSString *typedSecret = [self currentSecretValue];
    if (typedSecret == nil) {
        return;
    }

    self.secretVisibleField.stringValue = typedSecret;
    self.secretField.hidden = YES;
    self.secretVisibleField.hidden = NO;
    self.secretVisible = YES;
    self.secretToggleButton.title = @"Hide";
}

- (IBAction)copySecret:(id)sender {
    NSString *secret = [self currentSecretValue];
    if (secret == nil) {
        return;
    }
    if (secret.length == 0) {
        [self showError:@"No secret value to copy."];
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:secret forType:NSPasteboardTypeString];
    self.statusLabel.stringValue = @"Secret copied to clipboard";
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        InstallMainMenu();
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
