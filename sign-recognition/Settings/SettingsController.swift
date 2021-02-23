import Foundation
import UIKit

class SettingsController: UIViewController, UITextFieldDelegate {
    
    @IBOutlet weak var acceptTimeText: UITextField!
    @IBOutlet weak var timeoutText: UITextField!
    
    // changes status bar color to white
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    // This constraint ties an element at zero points from the bottom layout guide
    @IBOutlet var keyboardHeightLayoutConstraint: NSLayoutConstraint?
    
    @IBOutlet weak var usernameLabel: UILabel!
    var tokenString: String? = nil
    var userString: String? = nil
    
    var loadingSpinner: UIView? = nil
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.loadData()

        // enable auto lockscreen
        UIApplication.shared.isIdleTimerDisabled = false
        
        self.getUsername(tokenString: self.tokenString ?? "")
        
        acceptTimeText.delegate = self
        timeoutText.delegate = self
    }
    
    
    
    func loadData() {
        let defaults = UserDefaults.standard
        if let tokenString = defaults.string(forKey: "token") {
            print(tokenString)
            self.tokenString = tokenString
        }
        
        if let userString = defaults.string(forKey: "user") {
            print(userString)
            self.userString = userString
            self.usernameLabel.text = userString
        }
        
        if let recTime = defaults.string(forKey: "recTime") {
            self.acceptTimeText.text = recTime
        } else {
            self.initTimes()
        }
        
        if let timeout = defaults.string(forKey: "timeout") {
            self.timeoutText.text = timeout
        } else {
            self.initTimes()
        }
        
    }
    
    func initTimes() {
        let defaults = UserDefaults.standard
        
        let recTime = "60"
        let timeout = "150"
        
        defaults.set(recTime, forKey: "recTime")
        defaults.set(timeout, forKey: "timeout")
        
        self.acceptTimeText.text = recTime
        self.timeoutText.text = timeout

    }

    
    
    func connectionError() {
        let alert = UIAlertController(title: "Error", message: "No internet connection", preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: "Ok", style: .cancel) { _ in
            //NSAssertionHandler()
        }
        
        alert.addAction(okAction)
        
        present(alert, animated: true, completion: nil)
    }
    
    @IBAction func tapLogout(sender: AnyObject) {
        self.logOut()
    }
    
    func logOut() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "token")
        defaults.removeObject(forKey: "user")

        
        let settingsView = self.storyboard?.instantiateViewController(withIdentifier: "login")
        if let sview = settingsView{
            self.present(sview, animated: true)
        }
    }
    
    func removeToken() {
        let url = URL(string: "https://signrecognition.herokuapp.com/api/User/GetByToken/" + (self.tokenString ?? ""))!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let _ = data, error == nil else {
                //check for fundamental networking error
                print("Error removing token: \(String(describing: error))")
                return
            }
            
            if let httpStatus = response as? HTTPURLResponse {
                // check for http errors
                if httpStatus.statusCode != 200 {
                    DispatchQueue.main.async {
                        print("Token removal error: \(httpStatus.statusCode)")
                    }
                } else {
                    DispatchQueue.main.async {
                        print("Token removed")
                    }
                }
                
            }
        }
        task.resume()
   }
    
    
    func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
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
                    self.connectionError()
                }
                print("error=\(String(describing: error))")
                return
            }
            
            let responseString = String(data: data, encoding: .utf8)
            
            if let httpStatus = response as? HTTPURLResponse {
                    // check if user still logged in
                    if httpStatus.statusCode != 200 {
                    DispatchQueue.main.async {
                        self.loggedOut()
                    }
                }
                
            }
            
            print("responseString = \(String(describing: responseString))")
        }
        task.resume()
    }
    
    @IBAction func tapReset(sender: AnyObject) {
        self.initTimes()
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
    
    
    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        
        // Create an `NSCharacterSet` set which includes everything *but* the digits
        let inverseSet = NSCharacterSet(charactersIn:"0123456789").inverted
        
        // At every character in this "inverseSet" contained in the string,
        // split the string up into components which exclude the characters
        // in this inverse set
        let components = string.components(separatedBy: inverseSet)
        
        // Rejoin these components
        let filtered = components.joined(separator: "")
        
        return string == filtered
    }

    func textFieldShouldReturn(_ scoreText: UITextField) -> Bool {
        self.view.endEditing(true)
        return false
    }
    
    
    @IBAction func timeoutValueChanged(_ sender: Any) {
        let defaults = UserDefaults.standard
        defaults.set(self.timeoutText.text, forKey: "timeout")
    }
    
    @IBAction func acceptValueChanged(_ sender: Any) {
        let defaults = UserDefaults.standard
        defaults.set(self.acceptTimeText.text, forKey: "recTime")
    }

    
}
