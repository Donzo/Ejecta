#import <Foundation/Foundation.h>
#import "EJBindingBase.h"
#import "EJCanvasContext.h"
#import "EJCanvasContextTexture.h"

static const char * EJLineCapNames[] = {
	[kEJLineCapButt] = "butt",
	[kEJLineCapRound] = "round",
	[kEJLineCapSquare] = "square"
};

static const char * EJLineJoinNames[] = {
	[kEJLineJoinMiter] = "miter",
	[kEJLineJoinBevel] = "bevel",
	[kEJLineJoinRound] = "round"
};

static const char * EJTextBaselineNames[] = {
	[kEJTextBaselineAlphabetic] = "alphabetic",
	[kEJTextBaselineMiddle] = "middle",
	[kEJTextBaselineTop] = "top",
	[kEJTextBaselineHanging] = "hanging",
	[kEJTextBaselineBottom] = "bottom",
	[kEJTextBaselineIdeographic] = "ideographic"
};

static const char * EJTextAlignNames[] = {
	[kEJTextAlignStart] = "start",
	[kEJTextAlignEnd] = "end",
	[kEJTextAlignLeft] = "left",
	[kEJTextAlignCenter] = "center",
	[kEJTextAlignRight] = "right"
};

static const char * EJCompositeOperationNames[] = {
	[kEJCompositeOperationSourceOver] = "source-over",
	[kEJCompositeOperationLighter] = "lighter",
	[kEJCompositeOperationDarker] = "darker",
	[kEJCompositeOperationDestinationOut] = "destination-out",
	[kEJCompositeOperationDestinationOver] = "destination-over",
	[kEJCompositeOperationSourceAtop] = "source-atop",
	[kEJCompositeOperationXOR] = "xor"
};



@interface EJBindingCanvasContext : EJBindingBase {
	JSObjectRef jsCanvas;
	EJCanvasContext * renderingContext;
    EJApp * ejectaInstance;
}

- (id)initWithCanvas:(JSObjectRef)canvas renderingContext:(EJCanvasContext *)renderingContextp;

@end
