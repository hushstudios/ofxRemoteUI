//
//  AppDelegate.h.m
//  ofxRemoteUIClientOSX
//
//  Created by Oriol Ferrer Mesia on 8/28/11.
//  Copyright 2011 uri.cat. All rights reserved.
//

#import "Item.h"
#import "ItemCellView.h"
#import "AppDelegate.h"


@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {

	client = new ofxRemoteUIClient();
	
	// setup recent connections ///////////////

	//[[addressField cell] setSearchButtonCell:nil];
	[[addressField cell] setCancelButtonCell:nil];
	[[addressField cell] setSendsSearchStringImmediately:NO];
	[[addressField cell] setSendsActionOnEndEditing:NO];
	[addressField setRecentsAutosaveName:@"recentHosts"];

	NSMenu *cellMenu = [[NSMenu alloc] initWithTitle:@"Search Menu"];
	[cellMenu setAutoenablesItems:YES];
    NSMenuItem *item;

    item = [[NSMenuItem alloc] initWithTitle:@"Clear" action:nil keyEquivalent:@""];
    [item setTag:NSSearchFieldClearRecentsMenuItemTag];
	[item setTarget:self];
    [cellMenu insertItem:item atIndex:0];
	[item release];

    item = [NSMenuItem separatorItem];
    [item setTag:NSSearchFieldRecentsTitleMenuItemTag];
	[item setTarget:nil];
    [cellMenu insertItem:item atIndex:1];


    item = [[NSMenuItem alloc] initWithTitle:@"Recent Searches" action:NULL keyEquivalent:@""];
    [item setTag:NSSearchFieldRecentsTitleMenuItemTag];
	[item setTarget:nil];
    [cellMenu insertItem:item atIndex:2];
	[item release];


    item = [[NSMenuItem alloc] initWithTitle:@"Recents" action:NULL keyEquivalent:@""];
    [item setTag:NSSearchFieldRecentsMenuItemTag];
	[item setTarget:nil];
    [cellMenu insertItem:item atIndex:3];
	[item release];

    id searchCell = [addressField cell];
    [searchCell setSearchMenuTemplate:cellMenu];

	///////////////////////////////////////////////

	[self setup];
	timer = [NSTimer scheduledTimerWithTimeInterval:REFRESH_RATE target:self selector:@selector(update) userInfo:nil repeats:YES];
	statusTimer = [NSTimer scheduledTimerWithTimeInterval:STATUS_REFRESH_RATE target:self selector:@selector(statusUpdate) userInfo:nil repeats:YES];
	updateContinuosly = false;

	//connect to last used server by default
	NSUserDefaults * df = [NSUserDefaults standardUserDefaults];
	//NSLog(@"%@", [df stringForKey:@"lastAddress"]);
	if([df stringForKey:@"lastAddress"]) [addressField setStringValue:[df stringForKey:@"lastAddress"]];
	if([df stringForKey:@"lastPort"]) [portField setStringValue:[df stringForKey:@"lastPort"]];
	lagField.stringValue = @"";
	[self performSelector:@selector(connect) withObject:nil afterDelay:0.0];

	//get notified when window is resized
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(windowResized:) name:NSWindowDidResizeNotification
											   object: window];
}


- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender{
    return YES;
}


- (void)windowResized:(NSNotification *)notification;{

	for( map<string,Item*>::iterator ii = widgets.begin(); ii != widgets.end(); ++ii ){
		string key = (*ii).first;
		Item* t = widgets[key];
		[t remapSlider];
	}
}


-(NSString*)stringFromString:(string) s{
	return  [NSString stringWithCString:s.c_str() encoding:[NSString defaultCStringEncoding]];
}


-(BOOL)syncLocalParamsToClientParams{

	vector<string> paramList = client->getAllParamNamesList();
	vector<string> updatedParamsList = client->getChangedParamsList();

	//NSLog(@"Client holds %d params so far", (int) paramList.size());
	//NSLog(@"Client reports %d params changed since last check", (int)updatedParamsList.size());

	for(int i = 0; i < paramList.size(); i++){

		string paramName = paramList[i];
		RemoteUIParam p = client->getParamForName(paramName);

		map<string,Item*>::iterator it = widgets.find(paramName);
		if ( it == widgets.end() ){	//not found, this is a new param... lets make an UI item for it
			Item * row = [[Item alloc] initWithParam: p paramName: paramName];			
			keyOrder.push_back(paramName);
			widgets[paramName] = row;
			//[row remapSlider];
		}else{
			[widgets[paramName] updateValues:p];
			//if param has been changed, update the UI
			if(find(updatedParamsList.begin(), updatedParamsList.end(), paramName) != updatedParamsList.end()){ // found in list
				[widgets[paramName] updateUI];
				printf("updating UI for %s\n", paramName.c_str());
			}
		}
	}

	return ( client->hasReceivedUpdate() );
}


-(void)disableAllWidgets{
	for( map<string,Item*>::iterator ii = widgets.begin(); ii != widgets.end(); ++ii ){
		string key = (*ii).first;
		Item* t = widgets[key];
		[t disableChanges];
	}
}


-(void)enableAllWidgets{
	for( map<string,Item*>::iterator ii = widgets.begin(); ii != widgets.end(); ++ii ){
		string key = (*ii).first;
		Item* t = widgets[key];
		[t enableChanges];
	}
}


-(IBAction)pressedSync:(id)sender;{
	
	client->requestCompleteUpdate();
	//delay a bit the screen update so that we have gathered the values
	[self performSelector:@selector(handleUpdate:) withObject:nil afterDelay: REFRESH_RATE];
}

-(void) handleUpdate:(id)timer{

	if( [self syncLocalParamsToClientParams] ){ //if we update, refresh UI
		[tableView performSelector:@selector(reloadData) withObject:nil afterDelay: 0];
	}else{	// retry again in a while
		if(connectButton.state == 1){
			[self performSelector:@selector(handleUpdate:) withObject:nil afterDelay: 2 * REFRESH_RATE];
		}
		NSLog(@"no data yet; retry....");
	}
}


-(IBAction)pressedContinuously:(NSButton *)sender;{

	if(connectButton.state == 1){
		if ([sender state]) {
			[self disableAllWidgets];
			updateContinuosly = true;
			[updateFromServerButton setEnabled: false];
		}else{
			updateContinuosly = false;
			[updateFromServerButton setEnabled: true];
			[self enableAllWidgets];
		}
	}
}


-(IBAction)pressedConnect:(id)sender{
	//NSLog(@"pressedConnect");
	[self connect];
}


-(void) connect{
	
	//NSLog(@"connect!");
	NSUserDefaults * df = [NSUserDefaults standardUserDefaults];
	[df setObject: addressField.stringValue forKey:@"lastAddress"];
	[df setObject: portField.stringValue forKey:@"lastPort"];

	if ([[connectButton title] isEqualToString:@"Connect"]){ //we are not connected, let's connect
		widgets.clear();
		keyOrder.clear();
		[addressField setEnabled:false];
		[portField setEnabled:false];
		connectButton.title = @"Disconnect";
		connectButton.state = 1;
		NSLog(@"ofxRemoteUIClientOSX Connecting to %@", addressField.stringValue);
		int port = [portField.stringValue intValue];
		if (port < OFXREMOTEUI_PORT - 1) {
			port = OFXREMOTEUI_PORT - 1;
			portField.stringValue = [NSString stringWithFormat:@"%d", OFXREMOTEUI_PORT - 1];
		}
		client->setup([addressField.stringValue UTF8String], port);
		[updateFromServerButton setEnabled: true];
		[updateContinuouslyCheckbox setEnabled: true];
		[statusImage setImage:nil];
		//first load of vars
		[self performSelector:@selector(pressedSync:) withObject:nil afterDelay:0.15];
		[progress startAnimation:self];
		lagField.stringValue = @"";

	}else{ // let's disconnect

		[addressField setEnabled:true];
		[portField setEnabled:true];
		connectButton.state = 0;
		connectButton.title = @"Connect";
		[updateFromServerButton setEnabled: false];
		[updateContinuouslyCheckbox setEnabled:false];
		for( map<string,Item*>::iterator ii = widgets.begin(); ii != widgets.end(); ++ii ){
			string key = (*ii).first;
			Item* t = widgets[key];
			[t release];
		}
		widgets.clear();
		keyOrder.clear();
		[tableView reloadData];
		[statusImage setImage:[NSImage imageNamed:@"offline.png"]];
		[progress stopAnimation:self];
		lagField.stringValue = @"";
	}
}


- (void)windowDidResize:(NSNotification *)notification{

}



-(void)setup{
	//client->setup("127.0.0.1", 0.1);
}


-(void)statusUpdate{

	if (connectButton.state == 1){
		float lag = client->connectionLag();
		//printf("lag: %f\n", lag);
		if (lag > CONNECTION_TIMEOUT || lag < 0.0f){
			[self connect]; //force disconnect if lag is too large
			[progress stopAnimation:self];
			[statusImage setImage:[NSImage imageNamed:@"offline"]];
		}else{
			if (lag > 0.0f){
				lagField.stringValue = [NSString stringWithFormat:@"%.1fms", lag];
				[progress stopAnimation:self];
				[statusImage setImage:[NSImage imageNamed:@"connected.png"]];
			}
		}
	}
}


-(void)update{

	if ( connectButton.state == 1 ){ // if connected

		client->update(REFRESH_RATE);

		if(updateContinuosly){
			client->requestCompleteUpdate();
			[self syncLocalParamsToClientParams];
			[tableView reloadData];
		}

		if(!client->isReadyToSend()){	//if the other side disconnected, or error
			[self connect]; //this disconnects if we were connectd
		}
	}
}


//UI callback, we will get notified with this when user changes something in UI
-(void)userChangedParam:(RemoteUIParam)p paramName:(string)name{
	//NSLog(@"usr changed param! %s", name.c_str());
	if( connectButton.state == 1 ){
		//printf("client sending: "); p.print();
		client->sendParamUpdate(p, name);
	}
}


- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return widgets.size();
}


- (NSView *)tableView:(NSTableView *)myTableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {

	if (row <= keyOrder.size() && row >= 0){
		Item * item = widgets[ keyOrder[row] ];
		//NSLog(@"viewForTableColumn %@", item);
		ItemCellView *result = [myTableView makeViewWithIdentifier:tableColumn.identifier owner:self];
		//[result superview]

		if ( result.layer == nil){ // set bg color of widget
			if (item->param.a > 0 ){
				CALayer *viewLayer = [CALayer layer];
				[viewLayer setBackgroundColor:CGColorCreateGenericRGB(item->param.r / 255., item->param.g / 255., item->param.b / 255., item->param.a / 255.)];
				[result setWantsLayer:YES]; // view's backing store is using a Core Animation Layer
				[result setLayer:viewLayer];
			}
		}

		[item setCellView:result];
		[item remapSlider];
		[item updateUI];		

		//NSLog(@"item: %@", item);
		//result.detailTextField.stringValue = item.itemKind;
		return result;
	}else{
		return nil;
	}
}


- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row{
	return NO;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectTableColumn:(NSTableColumn *)tableColumn{
	return NO;
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)tableView;{
	return NO;
}


@end
