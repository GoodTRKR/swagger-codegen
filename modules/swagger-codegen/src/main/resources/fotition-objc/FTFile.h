#import <Foundation/Foundation.h>

@interface FTFile : NSObject

@property(nonatomic, readonly) NSString* name;
@property(nonatomic, readonly) NSString* mimeType;
@property(nonatomic, readonly) NSData* data;
@property(nonatomic) NSString* paramName;

- (id) initWithNameData: (NSString*) filename
               mimeType: (NSString*) mimeType
                   data: (NSData*) data;
    
@end