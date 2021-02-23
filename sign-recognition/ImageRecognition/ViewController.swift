import UIKit
import Vision
import AVFoundation
import CoreMedia
import VideoToolbox
import CoreLocation

class ViewController: UIViewController, CLLocationManagerDelegate {
    @IBOutlet weak var videoPreview: UIView!
    @IBOutlet weak var fpsLabel: UILabel!
    
    // token to verify user on server side
    var tokenString: String?
    
    // vibration feedback
    let nfGenerator = UINotificationFeedbackGenerator()
    
    // gps location manager
    let locationManager = CLLocationManager()
    var currentLocation: CLLocation? = nil
    
    var classTimeCountDict: [String: Int] = [:]
    
    let labelHeight:CGFloat = 50.0
    
    let yolo = YOLO()
    
    var send = true;
    
    var videoCapture: VideoCapture!
    var request: VNCoreMLRequest!
    var startTimes: [CFTimeInterval] = []
    
    var boundingBoxes = [BoundingBox]()
    var colors: [UIColor] = []
    
    let ciContext = CIContext()
    var resizedPixelBuffer: CVPixelBuffer?
    
    var framesDone = 0
    var frameCapturingStartTime = CACurrentMediaTime()
    let semaphore = DispatchSemaphore(value: 2)
    
    var recTime = 60
    var timeout = 120
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        // disable auto lockscreen
        UIApplication.shared.isIdleTimerDisabled = true
        
        // load data from memory
        self.loadData()
        
        // init location
        locationManager.requestWhenInUseAuthorization()

        
        setUpBoundingBoxes()
        setUpCoreImage()
        setUpCamera()
        
        frameCapturingStartTime = CACurrentMediaTime()
        
        // initialize location manager
        locationManager.requestWhenInUseAuthorization()
            if CLLocationManager.locationServicesEnabled() {
                locationManager.delegate = self
                locationManager.desiredAccuracy = kCLLocationAccuracyBest
                locationManager.startUpdatingLocation()
            } else {
                let alert = UIAlertController(title: "Alert", message: "GPS not enabled", preferredStyle: UIAlertController.Style.alert)
                self.present(alert, animated: true, completion: nil)
        }
    }
    
    func loadData() {
        let defaults = UserDefaults.standard
        if let token = defaults.string(forKey: "token") {
            print(token)
            self.tokenString = token
        } else {
            
            let loginView = self.storyboard?.instantiateViewController(withIdentifier: "login")
            if let lview = loginView{
                self.present(lview, animated: true)
            }
            
        }
        
        if let recTime = defaults.string(forKey: "recTime") {
            self.recTime = Int(recTime) ?? 60
        }
        
        if let timeout = defaults.string(forKey: "timeout") {
            self.timeout = Int(timeout) ?? 120
        }
        
    }
    
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            print(location.coordinate)
            currentLocation = location
        }
    }
    
    
    func setUpBoundingBoxes() {
        for _ in 0..<YOLO.maxBoundingBoxes {
            boundingBoxes.append(BoundingBox())
        }
        
        // Make colors for the bounding boxes. There is one color for each class,
        // 20 classes in total.
        for r: CGFloat in [0.1,0.2, 0.3,0.4,0.5, 0.6,0.7, 0.8,0.9, 1.0] {
            for g: CGFloat in [0.3,0.5, 0.7,0.9] {
                for b: CGFloat in [0.4,0.6 ,0.8] {
                    let color = UIColor(red: r, green: g, blue: b, alpha: 1)
                    colors.append(color)
                }
            }
        }
    }
    func setUpCoreImage() {
        let status = CVPixelBufferCreate(nil, YOLO.inputWidth, YOLO.inputHeight,
                                         kCVPixelFormatType_32BGRA, nil,
                                         &resizedPixelBuffer)
        if status != kCVReturnSuccess {
            print("Error: could not create resized pixel buffer", status)
        }
    }
    
    func setUpCamera() {
        videoCapture = VideoCapture()
        videoCapture.delegate = self
        videoCapture.fps = 60
        weak var welf = self
        
        videoCapture.setUp(sessionPreset: AVCaptureSession.Preset.inputPriority) { success in
            if success {
                // Add the video preview into the UI.
                if let previewLayer = welf?.videoCapture.previewLayer {
                    welf?.videoPreview.layer.addSublayer(previewLayer)
                    welf?.resizePreviewLayer()
                }
                
                
                // Add the bounding box layers to the UI, on top of the video preview.
                DispatchQueue.main.async {
                    guard let  boxes = welf?.boundingBoxes,let videoLayer  = welf?.videoPreview.layer else {return}
                    for box in boxes {
                        box.addToLayer(videoLayer)
                    }
                    welf?.semaphore.signal()
                }
                
                
                // Once everything is set up, we can start capturing live video.
                welf?.videoCapture.start()
                
                
                //     yolo.buffer(from: image)
                //        self.predict(pixelBuffer: self.yolo.buffer(from: image)!)
                
            }
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        resizePreviewLayer()
    }
    
    func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = videoPreview.bounds
    }
    
    
    func predict(pixelBuffer: CVPixelBuffer) {
        // Measure how long it takes to predict a single video frame.
        let startTime = CACurrentMediaTime()
        
        // Resize the input with Core Image to 416x416.
        guard let resizedPixelBuffer = resizedPixelBuffer else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sx = CGFloat(YOLO.inputWidth) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let sy = CGFloat(YOLO.inputHeight) / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaleTransform = CGAffineTransform(scaleX: sx, y: sy)
        let scaledImage = ciImage.transformed(by: scaleTransform)
        ciContext.render(scaledImage, to: resizedPixelBuffer)
        
        // This is an alternative way to resize the image (using vImage):
        //if let resizedPixelBuffer = resizePixelBuffer(pixelBuffer,
        //                                              width: YOLO.inputWidth,
        //                                              height: YOLO.inputHeight)
        
        // Resize the input to 416x416 and give it to our model.
        if let boundingBoxes = try? yolo.predict(image: resizedPixelBuffer) {
            let elapsed = CACurrentMediaTime() - startTime
            showOnMainThread(boundingBoxes, elapsed)
        }
    }
    
    
    func showOnMainThread(_ boundingBoxes: [YOLO.Prediction], _ elapsed: CFTimeInterval) {
        weak var welf = self
        
        DispatchQueue.main.async {
            // For debugging, to make sure the resized CVPixelBuffer is correct.
            //var debugImage: CGImage?
            //VTCreateCGImageFromCVPixelBuffer(resizedPixelBuffer, nil, &debugImage)
            //self.debugImageView.image = UIImage(cgImage: debugImage!)
            
            welf?.show(predictions: boundingBoxes)
            
            //if(self.send && boundingBoxes.count > 0){
            //welf?.send(predictions: boundingBoxes)
            //}
            
            guard  let fps = welf?.measureFPS() else{return}
            self.fpsLabel.text = String(format: "%.2f", fps)
            
            welf?.semaphore.signal()
        }
    }
    
    
    func show(predictions: [YOLO.Prediction]) {
        var classAppearedDict: [String: Bool] = [:]
        for i in 0..<boundingBoxes.count {
            if i < predictions.count {
                let prediction = predictions[i]
                
                // The predicted bounding box is in the coordinate space of the input
                // image, which is a square image of 416x416 pixels. We want to change aspect ratio to preview one
      
                // Translate and scale the rectangle to video preview
                var rect = prediction.rect
                rect.origin.x = (rect.origin.x/CGFloat(YOLO.inputWidth)) * self.videoPreview.bounds.width
                rect.origin.y = (rect.origin.y/CGFloat(YOLO.inputHeight)) * self.videoPreview.bounds.height
                rect.size.width = (rect.size.width/CGFloat(YOLO.inputWidth)) * self.videoPreview.bounds.width
                rect.size.height = (rect.size.height/CGFloat(YOLO.inputHeight)) * self.videoPreview.bounds.height
                
                // Show the bounding box.
                let label = String(format: "%@ %.1f", labels[prediction.classIndex], prediction.score)
                let color = colors[prediction.classIndex]
                boundingBoxes[i].show(frame: rect, label: label, color: color)
                
                classTimeCountDict[labels[prediction.classIndex]] = (classTimeCountDict[labels[prediction.classIndex]] ?? 0) + 1;
                
                classAppearedDict[labels[prediction.classIndex]] = true
                
            } else {
                boundingBoxes[i].hide()
            }
        }
        
        for prediction in classTimeCountDict {
            let notAppeared = !(classAppearedDict[prediction.key] ?? false)
            let currentCount = classTimeCountDict[prediction.key] ?? 0
            if  (notAppeared) {
                if currentCount > 0 {
                   classTimeCountDict[prediction.key] = max(currentCount - 1, 0)
                }
            } else {
                if(currentCount > recTime) {
                    self.signalRecognition()
                    sendPrediction(predictedClass: prediction.key)
                    classTimeCountDict[prediction.key] = -self.timeout
                }
            }
            
            if currentCount < 0 {
                classTimeCountDict[prediction.key] = currentCount + 1;
            }
        }
    }
    
    func signalRecognition() {
        // vibration
        nfGenerator.prepare()
        nfGenerator.notificationOccurred(.success)
        

        let aView = UIView(frame: self.view.frame)
        aView.isOpaque = false
        aView.backgroundColor = UIColor.white
        self.view.addSubview(aView)
        
        DispatchQueue.main.async {
            UIView.animate(withDuration: 1, delay: 0, options: [], animations: { () -> Void in
                aView.alpha = 0.0

            }, completion: { (done) -> Void in
                aView.removeFromSuperview()
            })
        }
    }
    
    func sendPrediction(predictedClass: String) {
        
        if currentLocation == nil {
            return
        }
        
        let lat = currentLocation?.coordinate.latitude ?? 0
        let lon = currentLocation?.coordinate.longitude ?? 0
        
        let jsonObject: [String: Any] = [
            "class": predictedClass,
            "latitude": String(format: "%f", lat),
            "longitude": String(format: "%f", lon),
            "token": self.tokenString ?? ""
        ]
        
        
        let url = URL(string: "https://signrecognition.herokuapp.com/api/Prediction/PostToken")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"

        let postJson = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)

        print(postJson ?? "JSON data empty")
            
        request.httpBody = postJson
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {                                                 // check for fundamental networking error
                print("error=\(String(describing: error))")
                return
            }
            
            if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 200 {
                if httpStatus.statusCode == 401 {
                    self.loggedOut()
                } else {
                    self.predError(code: httpStatus.statusCode)
                }
                
                // check for http errors
                print("statusCode should be 200, but is \(httpStatus.statusCode)")
                print("response = \(String(describing: response))")
            }
            
            let responseString = String(data: data, encoding: .utf8)
            print("responseString = \(String(describing: responseString))")
        }
        task.resume()
    }
    
    func measureFPS() -> Double {
        // Measure how many frames were actually delivered per second.
        framesDone += 1
        let frameCapturingElapsed = CACurrentMediaTime() - frameCapturingStartTime
        let currentFPSDelivered = Double(framesDone) / frameCapturingElapsed
        if frameCapturingElapsed > 1 {
            framesDone = 0
            frameCapturingStartTime = CACurrentMediaTime()
        }
        return currentFPSDelivered
    }
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    func predError(code: Int) {
        let alert = UIAlertController(title: "Error", message: "Http post error", preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: "Ok", style: .cancel) { _ in

        }
        
        alert.addAction(okAction)
        present(alert, animated: true, completion: nil)
    }
    
    
    func loggedOut() {
        
        let alert = UIAlertController(title: "Error", message: "You have been logged out", preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: "Ok", style: .cancel) { _ in
            DispatchQueue.main.async {
                self.logOut()
            }
        }
        
        alert.addAction(okAction)
        present(alert, animated: true, completion: nil)
    
    }
    
    func logOut() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "token")
        defaults.removeObject(forKey: "user")

        
        let settingsView = self.storyboard?.instantiateViewController(withIdentifier: "login")
        if let sview = settingsView{
            videoCapture.stop()
            self.present(sview, animated: true)
        }
    }
    
    @IBAction func returnButton(_ sender: Any) {
        videoCapture.stop()
    }
}


extension ViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        // For debugging.
        //    predict(image: UIImage(named: "bridge00508")!); return
        //    semaphore.wait()
        
        weak var welf = self
        if let pixelBuffer = pixelBuffer {
            // For better throughput, perform the prediction on a background queue
            // instead of on the VideoCapture queue. We use the semaphore to block
            // the capture queue and drop frames when Core ML can't keep up.
            DispatchQueue.global().async {
                welf?.predict(pixelBuffer: pixelBuffer)
                //        self.predictUsingVision(pixelBuffer: pixelBuffer)
            }
        }
    }
}
