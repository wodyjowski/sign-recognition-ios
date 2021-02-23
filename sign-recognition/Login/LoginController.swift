import Foundation
import UIKit

class LoginController: UIViewController, UITextFieldDelegate {
    
    // changes status bar color to white
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    var loadingSpinner: UIView? = nil
  
    @IBOutlet weak var login: UITextField!
    @IBOutlet weak var password: UITextField!
    
    @IBOutlet weak var keyboardConstraint: NSLayoutConstraint!
    
    

    var keyboardHeight: CGFloat = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.login.delegate = self
        self.password.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        self.keyboardHeight = self.keyboardConstraint.constant

    }
  
    @IBAction func tapRegister(sender: AnyObject) {
        if let url = URL(string: "https://signrecognition.herokuapp.com/register"){
            UIApplication.shared.open(url, options: [:],
                                      completionHandler: {
                                        (success) in
                                        print("Open: \(success)")
            })
        }
    }
    
    
    @IBAction func tapLogin(sender: AnyObject) {
        self.view.endEditing(true)
        loadingSpinner = UIViewController.displaySpinner(onView: self.view)
        
        if let uLogin = login.text, let uPassword = password.text {
                   authenticate(userLogin: uLogin, userPassword: uPassword)
        }
  
    }
    
    
    func authenticate(userLogin: String, userPassword: String) {
        
        let deviceName = UIDevice.current.name;
        
        let jsonObject: [String: Any] = [
            "UserName": userLogin,
            "Password": userPassword,
            "Name": deviceName
        ]
        
        
        let url = URL(string: "https://signrecognition.herokuapp.com/api/Login/AppToken")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        
        let postJson = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
        
        print(postJson ?? "JSON data empty")
        
        request.httpBody = postJson
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                //check for fundamental networking error
                DispatchQueue.main.async {
                    if let spinner = self.loadingSpinner{
                        UIViewController.removeSpinner(spinner: spinner)
                    }
                    self.connectionError();
                }
                print("error=\(String(describing: error))")
                return
            }
            
            let responseString = String(data: data, encoding: .utf8)
            
            if let httpStatus = response as? HTTPURLResponse {
                // check for http errors
                if httpStatus.statusCode != 200 {
                    DispatchQueue.main.async {
                        self.loginError()
                        print("statusCode should be 200, but is \(httpStatus.statusCode)")
                        print("response = \(String(describing: response))")
                    }
                } else {
                    DispatchQueue.main.async {
                        self.loginOk(text: responseString)
                    }
                }
                DispatchQueue.main.async {
                    if let spinner = self.loadingSpinner{
                       UIViewController.removeSpinner(spinner: spinner)
                    }
                }
            }

            print("responseString = \(String(describing: responseString))")
        }
        task.resume()
        
    }
    
    func loginError() {
        let alert = UIAlertController(title: "Login failed", message: "Invalid login or password", preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: "Ok", style: .cancel) { _ in
            //NSAssertionHandler()
        }
        
        alert.addAction(okAction)
        
        present(alert, animated: true, completion: nil)
    }
    
    func loginOk(text: String?) {
        
        if let token = text {
            let defaults = UserDefaults.standard
            defaults.set(token, forKey: "token")
            
            self.getUsername(tokenString: token)
        }
    }
    
    func connectionError() {
        let alert = UIAlertController(title: "Error", message: "No internet connection", preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: "Ok", style: .cancel) { _ in
        }
        
        alert.addAction(okAction)
        
        present(alert, animated: true, completion: nil)
    }
    
    
    
    func getUsername(tokenString: String) {
        
        let url = URL(string: "https://signrecognition.herokuapp.com/api/User/GetByToken/" + tokenString)!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                //check for fundamental networking error
                DispatchQueue.main.async {
                    self.usernameError()
                    self.loginError()
                }
                print("error=\(String(describing: error))")
                return
            }
            
            let responseString = String(data: data, encoding: .utf8)
            
            if let httpStatus = response as? HTTPURLResponse {
                // check for http errors
                if httpStatus.statusCode != 200 {
                    DispatchQueue.main.async {
                        self.usernameError()
                        self.loginError()
                    }
                } else {
                    let defaults = UserDefaults.standard
                    defaults.set(responseString, forKey: "user")
                    DispatchQueue.main.async {
                        self.endLogin();
                    }
                }

            }
            
            print("responseString = \(String(describing: responseString))")
        }
        task.resume()
    }
    
    func usernameError() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "token")
        defaults.removeObject(forKey: "user")
    }
    
    func endLogin() {
        let settingsView = self.storyboard?.instantiateViewController(withIdentifier: "settings")
        if let sview = settingsView{
            self.present(sview, animated: true)
        }
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func keyboardWillShow(notification: Notification) {

        
        self.moveKeyboard(notification: notification, value: self.keyboardHeight - 80)
    }

    @objc func keyboardWillHide(notification: Notification) {
            self.moveKeyboard(notification:notification, value: keyboardHeight)
    }
    
    func moveKeyboard(notification: Notification, value: CGFloat) {
      if let userInfo = notification.userInfo {
        let endFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        let duration:TimeInterval = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        let animationCurveRawNSN = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber
        let animationCurveRaw = animationCurveRawNSN?.uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        let animationCurve:UIView.AnimationOptions = UIView.AnimationOptions(rawValue: animationCurveRaw)
        
        self.keyboardConstraint.constant = value
        
        UIView.animate(withDuration: duration,
                       delay: TimeInterval(0),
                       options: animationCurve,
                       animations: { self.view.layoutIfNeeded() },
                       completion: nil)
       }
    }
    
    func textFieldShouldReturn(_ scoreText: UITextField) -> Bool {
        self.view.endEditing(true)
        return false
    }

}
