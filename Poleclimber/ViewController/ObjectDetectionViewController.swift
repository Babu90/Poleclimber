//
//  ObjectDetectionViewController.swift
//  Poleclimber
//
//  Created by Siva Preasad Reddy on 31/03/20.
//  Copyright © 2020 Siva Preasad Reddy. All rights reserved.
//

import UIKit
import AVKit
import Vision
import RMessage

class ObjectDetectionViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate, NavigationDelegate {
    @IBOutlet weak var buttonsView: UIView!
    @IBOutlet weak var boxesView: DrawingBoundingBoxView!
    @IBOutlet weak var namelabel: UILabel!

    @IBOutlet var poleStatusSubView: PoleStatusView!
    var predictions: [VNRecognizedObjectObservation] = []
    let objectDectectionModel =  MobileNetV3_SSDLite() //YOLOv3Tiny()
    @IBOutlet weak var noImgView: UIView!
    var imagePicker:UIImagePickerController!
    @IBOutlet weak var imageView: UIImageView!
    var detectBtn = UIBarButtonItem()
    var cvpixelBuffer: CVPixelBuffer!
    let rControl = RMController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
  
        self.navigationController?.isNavigationBarHidden = false
        self.title = "Visual inspection"
        imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        
        buttonsView.isHidden = true
        namelabel.isHidden = true
        
        detectBtn = UIBarButtonItem(title: "Detect", style: .plain, target: self, action: #selector(detectObjects))
        navigationItem.rightBarButtonItem = detectBtn
        detectBtn.isEnabled = false
        
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
    }
    
    @objc func detectObjects() {
        Helper.sharedHelper.showGlobalHUD(title: "Processing...", view: view)

        if Helper.sharedHelper.isNetworkAvailable() {
            perform(#selector(detectSubImagesInImg), with: nil, afterDelay: 2)
        }
        else{
           rControl.showMessage(withSpec: warningSpec, title: "Info", body: "You don't have internet connection so classification will run using ios ML model.")
            perform(#selector(detectSubImagesInImg), with: nil, afterDelay: 2)
        }
    }
    
    @objc func detectSubImagesInImg() {
        captureImageDetails(pixelBuffer: cvpixelBuffer!)
    }
    
    @IBAction func addPicture(sender: UIButton) {
        let alert = UIAlertController(title: "Take Photo", message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Camera", style: .default, handler: { (action) in
                self.openCamera()
        }))
        alert.addAction(UIAlertAction(title: "Gallery", style: .default, handler: { (action) in
                self.openGallary()
        }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    func openCamera() {
        if (UIImagePickerController.isSourceTypeAvailable(UIImagePickerController.SourceType.camera)) {
            imagePicker.sourceType = UIImagePickerController.SourceType.camera
            self.present(imagePicker, animated: true, completion: nil)
        }
        else{
            Helper.sharedHelper.showGlobalAlertwithMessage("You don't have camera.")
        }
    }
    
    func openGallary() {
        imagePicker.sourceType = UIImagePickerController.SourceType.photoLibrary
        self.present(imagePicker, animated: true, completion: nil)
    }
    
    // MARK: - UIImagePickerControllerDelegate Method
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
            
            UIGraphicsBeginImageContextWithOptions(CGSize(width: 299, height: 299), true, 2.0)
            image.draw(in: CGRect(x: 0, y: 0, width: 299, height: 299))
            let newImage = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()
                   
            let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
            var pixelBuffer : CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(newImage.size.width), Int(newImage.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
            guard (status == kCVReturnSuccess) else {
                return
            }
                   
            CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
            let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
                   
            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(data: pixelData, width: Int(newImage.size.width), height: Int(newImage.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) //3
                   
            context?.translateBy(x: 0, y: newImage.size.height)
            context?.scaleBy(x: 1.0, y: -1.0)
                   
            UIGraphicsPushContext(context!)
            newImage.draw(in: CGRect(x: 0, y: 0, width: newImage.size.width, height: newImage.size.height))
            UIGraphicsPopContext()
            CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
            imageView.image = newImage
            cvpixelBuffer = pixelBuffer

            showAddImgView()

            self.dismiss(animated: true, completion: nil)
        }
    }
    
     func showAddImgView() {
        noImgView.isHidden = true
        detectBtn.isEnabled = true
    }
    
    // MARK: - Capture Session
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
          showAddImgView()

        // Get the pixel buffer from the capture session
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        cvpixelBuffer = pixelBuffer
    }
    
    func captureImageDetails(pixelBuffer: CVPixelBuffer)  {
          // load the Core ML model
        guard let visionModel:VNCoreMLModel = try? VNCoreMLModel(for: objectDectectionModel.model) else { return }
        //  set up the classification request
        let request = VNCoreMLRequest(model: visionModel){(finishedReq, error) in
                    
        guard let result = finishedReq.results as? [VNRecognizedObjectObservation] else {
            return
        }
            
        Helper.sharedHelper.dismissHUD(view: self.view)
      guard result.first != nil else {
        self.rControl.showMessage(withSpec: errorSpec, title: "Error", body: "We didn't found any tip rot, please select proper pole tip image for ML Model.")
        self.imageView.image = UIImage(named: "")
        self.noImgView.isHidden = false
        self.detectBtn.isEnabled = false
        return
      }

        self.predictions = result
        DispatchQueue.main.async {
          self.buttonsView.isHidden = false
          self.namelabel.isHidden = false
            if self.predictions.first?.label == "good_tip" {
                self.namelabel.text = "We found Good tip"
            }
            else{
                self.namelabel.text = "We found Bad tip"
            }

          //let objectBounds = VNImageRectForNormalizedRect(result[0].boundingBox, Int(self.videoPreview.frame.size.width), Int(self.videoPreview.frame.size.height))

          self.boxesView.predictedObjects = self.predictions
          }
             //print(firstObservation.identifier, firstObservation.confidence)
        }
                
        request.imageCropAndScaleOption = .scaleFill
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
    }
    
    @IBAction func AgreeBtnAction(_ sender: Any) {
        rControl.showMessage(withSpec: successSpec, title: "Success", body: "Your feedback saved successfully.")
        perform(#selector(navigateToHomeScreen), with: nil, afterDelay: 2)
    }
    
    @objc func navigateToHomeScreen() {
        self.navigationController?.popViewController(animated: true)
    }
    
    @IBAction func disAgreeBtnAction(_ sender: Any) {
        poleStatusSubView.frame = view.bounds
        poleStatusSubView.delegate = self
        view.addSubview(poleStatusSubView)
    }
    
    func submitBtnAction() {
        rControl.showMessage(withSpec: successSpec, title: "Success", body: "Thank you for your reason, we will get back to you.")
        perform(#selector(navigateToHomeScreen), with: nil, afterDelay: 2)
    }
}
