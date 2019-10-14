import UIKit
import AVFoundation
import Photos
import VideoToolbox

@available(iOS 11.1, *)
class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    @IBOutlet weak var cameraView: UIView!
    
    let session: AVCaptureSession = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInTrueDepthCamera],
        mediaType: .video,
        position: .front)
    
    private let sessionQueue = DispatchQueue(label: "SessionQueue", attributes: [], autoreleaseFrequency: .workItem)
    private let processingQueue = DispatchQueue(label: "photo processing queue", attributes: [], autoreleaseFrequency: .workItem)
    
    private let photoDepthConverter = DepthToGrayscaleConverter()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        /* setup input and output */
        let videoDevice: AVCaptureDevice? = videoDeviceDiscoverySession.devices.first
        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice!), session.canAddInput(videoDeviceInput)
            else {
                print("Cannot addd input")
                return
        }
        
        session.beginConfiguration()
        
        session.addInput(videoDeviceInput)
        
        guard session.canAddOutput(photoOutput) else {
            print("cannot add photo output")
            return
        }
        session.addOutput(photoOutput)
        session.sessionPreset = .photo
        
        session.commitConfiguration()
        
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
                
        
        /* capture depth information */

//        session.beginConfiguration()
//
//        let depthFormats = videoDevice!.activeFormat.supportedDepthDataFormats
//        let filtered = depthFormats.filter({
//            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat16
//        })
//        let selectedFormat = filtered.max(by: {
//            first, second in CMVideoFormatDescriptionGetDimensions(first.formatDescription).width < CMVideoFormatDescriptionGetDimensions(second.formatDescription).width
//        })
//
//        do {
//            try videoDevice!.lockForConfiguration()
//            videoDevice!.activeDepthDataFormat = selectedFormat
//            videoDevice!.unlockForConfiguration()
//        } catch {
//            print("Could not lock device for configuration: \(error)")
//            session.commitConfiguration()
//            return
//        }
//
//        session.commitConfiguration()

        
        /* add live preview */
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        videoPreviewLayer?.frame = cameraView.layer.bounds
        cameraView.layer.addSublayer(videoPreviewLayer!)
        
        session.startRunning()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        print("captured")
        
        processingQueue.async {
            
            if let depthData = photo.depthData {
                let depthPixelBuffer = depthData.depthDataMap
                
                if !self.photoDepthConverter.isPrepared {
                    var depthFormatDescription: CMFormatDescription?
                    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                                 imageBuffer: depthPixelBuffer,
                                                                 formatDescriptionOut: &depthFormatDescription)
                    
                    /*
                     outputRetainedBufferCountHint is the number of pixel buffers we expect to hold on to from the renderer.
                     This value informs the renderer how to size its buffer pool and how many pixel buffers to preallocate.
                     Allow 3 frames of latency to cover the dispatch_async call.
                     */
                    if let unwrappedDepthFormatDescription = depthFormatDescription {
                        self.photoDepthConverter.prepare(with: unwrappedDepthFormatDescription, outputRetainedBufferCountHint: 3)
                    }
                }
                
                guard let convertedDepthPixelBuffer = self.photoDepthConverter.render(pixelBuffer: depthPixelBuffer) else {
                    print("Unable to convert depth pixel buffer")
                    return
                }
                
                let greyImage = UIImage.init(pixelBuffer: convertedDepthPixelBuffer)
                
                UIImageWriteToSavedPhotosAlbum(greyImage!, nil, nil, nil)

            }
        }
        
        //photo.fileDataRepresentation()
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: photo.fileDataRepresentation()!, options: nil)
            }, completionHandler: nil)
        }
    }
    
    func getSettings() -> AVCapturePhotoSettings {
        let setting = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        setting.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        return setting
    }
    
    @IBAction func capture(_ sender: UIButton) {
        sessionQueue.async {
            self.photoOutput.capturePhoto(with: self.getSettings(), delegate: self)
        }
        
        /* button vibrate*/
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        /* photo capture animation */
        self.cameraView.layer.opacity = 0
        UIView.animate(withDuration: 0.25) {
            self.cameraView.layer.opacity = 1
        }
    }
    
    @objc
    func didEnterBackground(notification: NSNotification) {
        // Free up resources.
        processingQueue.async {
            self.photoDepthConverter.reset()
        }
    }
}


extension UIImage {
    public convenience init?(pixelBuffer: CVPixelBuffer) {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

        if let cgImage = cgImage {
            self.init(cgImage: cgImage, scale: 1.0, orientation: Orientation.right)
        } else {
            return nil
        }
    }
}
