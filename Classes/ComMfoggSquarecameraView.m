
// original via github.com/mikefogg/SquareCamera

// Modifications / Attempts to fix using ramdom bit of code found here and there : Kosso : August 2013

#import "ComMfoggSquarecameraView.h"
#import "ComMfoggSquarecameraViewProxy.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreMedia/CoreMedia.h>


@implementation ComMfoggSquarecameraView

// used for KVO observation of the @"capturingStillImage" property to perform flash bulb animation
static const NSString *AVCaptureStillImageIsCapturingStillImageContext = @"AVCaptureStillImageIsCapturingStillImageContext";

- (void) dealloc
{
    NSLog(@"[DEBUG] Just entered dealloc method ...");
    
	[self teardownAVCapture];

	self.prevLayer = nil;
	self.stillImage = nil;
	self.stillImageOutput = nil;
	self.captureDevice = nil;

	RELEASE_TO_NIL(square);

	[super dealloc];
}

-(void)initializeState
{
    NSLog(@"[DEBUG] Just entered initializeState method ...");

	[super initializeState];

	self.prevLayer = nil;
	self.stillImage = nil;
	self.stillImageOutput = nil;
	self.captureDevice = nil;

  // Set defaults
  self.camera = @"back"; // Default camera is 'back'
}

-(void)frameSizeChanged:(CGRect)frame bounds:(CGRect)bounds
{
    NSLog(@"[DEBUG] Just entered frameSizeChanged method ...");

    // This is initializing the square view
  	[TiUtils setView:self.square positionRect:bounds];
}

- (void)turnFlashOn:(id)args
{
    NSLog(@"[DEBUG] Just entered turnFlashOn method ...");

	if([self.captureDevice lockForConfiguration:true]){
        if([self.captureDevice isFlashModeSupported:AVCaptureFlashModeOn]){
            [self.captureDevice setFlashMode:AVCaptureFlashModeOn];
            self.flashOn = YES;
            [self.captureDevice lockForConfiguration:false];
            
            [self.proxy fireEvent:@"onFlashOn"];
        };
    };
};

- (void)turnFlashOff:(id)args
{
    NSLog(@"[DEBUG] Just entered turnFlashOff method ...");

	if([self.captureDevice lockForConfiguration:true]){
        if([self.captureDevice isFlashModeSupported:AVCaptureFlashModeOn]){
            [self.captureDevice setFlashMode:AVCaptureFlashModeOff];
            self.flashOn = NO;  
            [self.captureDevice lockForConfiguration:false];

            [self.proxy fireEvent:@"onFlashOff"];
        };
	};
};

// utility routine to display error alert if takePicture fails
- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message
{
    NSLog(@"[DEBUG] Just entered displayErrorOnMainQueue method ...");

	dispatch_async(dispatch_get_main_queue(), ^(void) {
		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%d)", message, (int)[error code]]
			message:[error localizedDescription]
			delegate:nil 
			cancelButtonTitle:@"Dismiss" 
			otherButtonTitles:nil];
		[alertView show];
		[alertView release];
	});
}

- (void)takePhoto:(id)args
{
    NSLog(@"[DEBUG] Just entered takePhoto method ...");
    NSLog(@"args = %@", args);

	AVCaptureConnection *stillImageConnection = nil;

	for (AVCaptureConnection *connection in self.stillImageOutput.connections)
	{
		for (AVCaptureInputPort *port in [connection inputPorts])
		{
			if ([[port mediaType] isEqual:AVMediaTypeVideo] )
			{
				stillImageConnection = connection;
				break;
			}
		}
		if (stillImageConnection) { break; }
	}

	UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];

	[self.stillImageOutput captureStillImageAsynchronouslyFromConnection:stillImageConnection completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error)
	{ 

		CFDictionaryRef exifAttachments = CMGetAttachment(imageSampleBuffer, kCGImagePropertyExifDictionary, NULL);
		if (exifAttachments) {
			NSLog(@"[INFO] imageSampleBuffer Exif attachments: %@", exifAttachments);
		} else { 
			NSLog(@"[INFO] No imageSampleBuffer Exif attachments");
		}

		NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];    

		UIImage *image = [[UIImage alloc] initWithData:imageData];

          CGSize size = image.size;  // this will be the full size of the screen 

          NSLog(@"image.size : %@", NSStringFromCGSize(size));

          CGFloat image_width = self.stillImage.frame.size.width*2;
          CGFloat image_height = self.stillImage.frame.size.height*2;

          CGRect cropRect = CGRectMake(
          	0,
          	0,
          	image_width,
          	image_height
          	);

          NSLog(@"cropRect : %@", NSStringFromCGRect(cropRect));


          CGRect customImageRect = CGRectMake(
          	-((((cropRect.size.width/size.width)*size.height)-cropRect.size.height)/2),
          	0,
          	((cropRect.size.width/size.width)*size.height),
          	cropRect.size.width);
          
          UIGraphicsBeginImageContext(cropRect.size);
          CGContextRef context = UIGraphicsGetCurrentContext();  
          
          CGContextScaleCTM(context, 1.0, -1.0);  
          CGContextRotateCTM(context, -M_PI/2);  
          
          CGContextDrawImage(context, customImageRect,
          	image.CGImage);
          
          UIImage *croppedImage = UIGraphicsGetImageFromCurrentImageContext();  
          UIGraphicsEndImageContext();          
          
          TiBlob *imageBlob = [[TiBlob alloc] initWithImage:[self flipImage:croppedImage]]; // maybe try image here 
          NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
																self.camera, @"camera",
																imageBlob, @"media",
																nil];
          
          // HURRAH! 
          [self.proxy fireEvent:@"success" withObject:event];

        }];
}

-(UIImage *)flipImage:(UIImage *)img
{
	UIImage* flippedImage = img;

	if([self.camera isEqualToString: @"front"]){
  	flippedImage = [UIImage imageWithCGImage:img.CGImage scale:img.scale orientation:(img.imageOrientation + 4) % 8];
  };

  return flippedImage;
}

-(void)setCamera_:(id)value
{
    NSLog(@"[DEBUG] Just entered setCamera_ method ...");
    NSLog(@"value = %@", value);
    
	NSString *camera = [TiUtils stringValue:value];

	if (![camera isEqualToString: @"front"] && ![camera isEqualToString: @"back"]) {
		NSLog(@"[ERROR] Attempted to set camera that is not front or back... ignoring.");
	} else {
		self.camera = camera;

		[self setCaptureDevice];

		NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
			self.camera, @"camera",
			nil];

		[self.proxy fireEvent:@"onCameraChange" withObject:event];
	}
}

-(void)pause:(id)args
{
    NSLog(@"[DEBUG] Just entered pause method ...");
    NSLog(@"self.captureSession = %@", self.captureSession);
    NSLog(@"args = %@", args);

    if(self.captureSession){
        if([self.captureSession isRunning]){
            [self.captureSession stopRunning];
            
            NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"paused", @"state",
                                   nil];
            
            [self.proxy fireEvent:@"stateChange" withObject:event];

        } else {
            NSLog(@"[ERROR] Attempted to pause an already paused session... ignoring.");
        };
    } else {
        NSLog(@"[ERROR] Attempted to pause the camera before it was started... ignoring.");
    };
};

-(void)resume:(id)args
{
    NSLog(@"[DEBUG] Just entered resume method ...");
    NSLog(@"self.captureSession = %@", self.captureSession);
    NSLog(@"args = %@", args);
    
    if(self.captureSession){
        if(![self.captureSession isRunning]){
            [self.captureSession startRunning];
            
            NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"resumed", @"state",
                                   nil];
            
            [self.proxy fireEvent:@"stateChange" withObject:event];

        } else {
            NSLog(@"[ERROR] Attempted to resume an already running session... ignoring.");
        };
    } else {
        NSLog(@"[ERROR] Attempted to resume the camera before it was started... ignoring.");
    };
};

-(void)setCaptureDevice
{
    NSLog(@"[DEBUG] Just entered setCaptureDevice method ...");
	AVCaptureDevicePosition desiredPosition;
	
	if ([self.camera isEqualToString: @"back"]){
		desiredPosition = AVCaptureDevicePositionBack;

		if([self.captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080] == YES)
		{
			self.captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
		} else {
			self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
		}

	} else {
		desiredPosition = AVCaptureDevicePositionFront;
		self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
	};
    
    for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
		if ([d position] == desiredPosition) {
			[[self.prevLayer session] beginConfiguration];
            
			AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:d error:nil];
            
			for (AVCaptureInput *oldInput in [[self.prevLayer session] inputs]) {
				[[self.prevLayer session] removeInput:oldInput];
			}
			[[self.prevLayer session] addInput:input];
			[[self.prevLayer session] commitConfiguration];
			break;
		};
	};
}

-(UIView*)square
{
    NSLog(@"[DEBUG] Just entered square method ...");
    NSLog(@"square = %@", square);

	if (square == nil) {

		square = [[UIView alloc] initWithFrame:[self frame]];
        NSLog(@"[DEBUG] created new UIView for square ...");
		[self addSubview:square];
        NSLog(@"[DEBUG] added square as a Subview ...");

		self.stillImage = [[UIImageView alloc] init];
		self.stillImage.frame = [square bounds];
		[self addSubview:self.stillImage];

        NSLog(@"[DEBUG] about to call isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera ...");
		if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {

			self.captureSession = [[AVCaptureSession alloc] init];
            NSLog(@"[DEBUG] called AVCaptureSession alloc init ...");

			self.prevLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.captureSession];
            NSLog(@"[DEBUG] called AVCaptureVideoPreviewLayer alloc initWithSession:self.captureSession ...");
			self.prevLayer.frame = self.square.bounds;
			self.prevLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
			[self.square.layer addSublayer:self.prevLayer];
            NSLog(@"[DEBUG] called [self.square.layer addSublayer:self.prevLayer] ...");

			self.captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            NSLog(@"[DEBUG] called captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] ...");

			if ([self.captureDevice lockForConfiguration:true]) {
                NSLog(@"[DEBUG] in [self.captureDevice lockForConfiguration:true] ...");
                
                if ([self.captureDevice isFlashModeSupported:AVCaptureFlashModeOff]) {
                    [self.captureDevice setFlashMode:AVCaptureFlashModeOff];
                    self.flashOn = NO;
                };
                
				[self.captureDevice lockForConfiguration:false];
			};

			// Set the default camera
            NSLog(@"[DEBUG] about to \"Set the default camera\" [self setCaptureDevice] ...");
			[self setCaptureDevice];

			NSError *error = nil;
			
            NSLog(@"[DEBUG] about to [[[AVCaptureVideoDataOutput alloc] init] autorelease] ...");
			self.videoDataOutput = [[[AVCaptureVideoDataOutput alloc] init] autorelease];
            [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES]; // discard if the data output queue is blocked (as we process the still image)

            // Now do the dispatch queue .. 
            NSLog(@"[DEBUG] about to \"Now do the dispatch queue\" [self setCaptureDevice] ...");
            videoDataOutputQueue = dispatch_queue_create("videoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
            [self.videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];

            NSLog(@"[DEBUG] about to [[AVCaptureStillImageOutput alloc] init] ...");
            self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];

            NSLog(@"[DEBUG] about to [self.stillImageOutput addObserver:self forKeyPath:@\"capturingStillImage\" ...");
            [self.stillImageOutput addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:AVCaptureStillImageIsCapturingStillImageContext];

            NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys: AVVideoCodecJPEG, AVVideoCodecKey, nil];
            NSLog(@"[DEBUG] about to [self.stillImageOutput setOutputSettings:outputSettings] ...");
            [self.stillImageOutput setOutputSettings:outputSettings];

            NSLog(@"[DEBUG] about to [self.captureSession addOutput:self.stillImageOutput] ...");
            [self.captureSession addOutput:self.stillImageOutput];
            
            [outputSettings release];

            NSLog(@"[DEBUG] about to [NSDictionary dictionaryWithObject ...");
            NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:
            	[NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];

            NSLog(@"[DEBUG] about to [self.videoDataOutput setVideoSettings:rgbOutputSettings] ...");
            [self.videoDataOutput setVideoSettings:rgbOutputSettings];

            NSLog(@"[DEBUG] about to [self.captureSession addOutput:self.videoDataOutput] ...");
            [self.captureSession addOutput:self.videoDataOutput];

            NSLog(@"[DEBUG] about to [[self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:NO]; ...");
            [[self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:NO];

            // and off we go! ...
            NSLog(@"[DEBUG] about to [self.captureSession startRunning] ...");
            [self.captureSession startRunning];
            
            NSLog(@"[DEBUG] about to [NSDictionary dictionaryWithObject ...");
            NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"started", @"state",
                                   nil];
            
            NSLog(@"[DEBUG] about to [NSDictionary dictionaryWithObject ...");
            [self.proxy fireEvent:@"stateChange" withObject:event];

            // uh oh ... 
            bail:
            NSLog(@"[DEBUG] in the \"bail:\", and about to [self.captureSession release] ...");
            NSLog(@"bail: error = %@", error);
            [self.captureSession release];
            if (error) {
            	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Failed with error %d", (int)[error code]]
            		message:[error localizedDescription]
            		delegate:nil 
            		cancelButtonTitle:@"oh dear" 
            		otherButtonTitles:nil];
            	[alertView show];
            	[alertView release];
            	[self teardownAVCapture];
            }

        } else {
            // If camera is NOT avaialble
            NSLog(@"[DEBUG] in the \"If camera is NOT avaialble\", and about to [self.proxy fireEvent:@\"noCamera\"] ...");
            [self.proxy fireEvent:@"noCamera"];
        }
        /////////////////////////////////////////////////////////////////////////////
    }

    return square;
}



- (void)teardownAVCapture
{

    NSLog(@"[INFO] TEAR DOWN CAPTURE");

    [self.captureSession removeInput:self.videoInput];
    [self.captureSession removeOutput:self.videoDataOutput];

    [self.captureSession stopRunning];
    
    NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"stopped", @"state",
                           nil];
    
    [self.proxy fireEvent:@"stateChange" withObject:event];

    [_videoDataOutput release];
    if (videoDataOutputQueue)
    	dispatch_release(videoDataOutputQueue);
    [self.stillImageOutput removeObserver:self forKeyPath:@"capturingStillImage"];
    [self.stillImageOutput release];
    [self.prevLayer removeFromSuperlayer];
    [self.prevLayer release];
}

// perform a flash bulb animation using KVO to monitor the value of the capturingStillImage property of the AVCaptureStillImageOutput class
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSLog(@"[DEBUG] Just entered observeValueForKeyPath method ...");

	if ( context == AVCaptureStillImageIsCapturingStillImageContext ) {
		BOOL isCapturingStillImage = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
		if ( isCapturingStillImage ) {
      // do flash bulb like animation
			flashView = [[UIView alloc] initWithFrame:[self.stillImage frame]];
			[flashView setBackgroundColor:[UIColor whiteColor]];
			[flashView setAlpha:0.f];

			[self addSubview:flashView];
      // fade it in            
			[UIView animateWithDuration:.3f
				animations:^{
					[flashView setAlpha:1.f];
				}
				];
		}
		else {
      // fade it out
			[UIView animateWithDuration:.3f
				animations:^{
					[flashView setAlpha:0.f];
				}
				completion:^(BOOL finished){
          // get rid of it
					[flashView removeFromSuperview];
					[flashView release];
					flashView = nil;
				}
				];
		}
	}
}

// utility routing used during image capture to set up capture orientation
- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
    NSLog(@"[DEBUG] Just entered avOrientationForDeviceOrientation method ...");

	AVCaptureVideoOrientation result = deviceOrientation;
	if ( deviceOrientation == UIDeviceOrientationLandscapeLeft )
		result = AVCaptureVideoOrientationLandscapeRight;
	else if ( deviceOrientation == UIDeviceOrientationLandscapeRight )
		result = AVCaptureVideoOrientationLandscapeLeft;
	return result;
}

@end
