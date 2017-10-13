import UIKit
import Incremental


extension Color {
    var name: String {
        switch self {
        case .red: return "rot"
        case .turquoise: return "tuerkis"
        case .brightGreen: return "hellgruen"
        case .beige: return "beige"
        case .green: return "gruen"
        case .purple: return "lila"
        case .violet: return "violett"
        case .blue: return "blau"
        case .brown: return "braun"
        case .yellow: return "gelb"
        case .gray: return "grau"
        case .lightBlue: return "hellblau"
        case .lightBrown: return "hellbraun"
        case .orange: return "orange"
        case .pink: return "pink"
        case .lightPink: return "rosa"
        }
    }
}


enum Command<Message> {
}

struct State: Reducer {
    private(set) var modal1Presented: Bool
    private(set) var modal2Presented: Bool

    enum Message {
        case present1
        case present2
    }


    mutating func send(_ message: Message) -> Command<Message>? {
        switch message {
        case .present1:
            modal1Presented = true
            return nil
        case .present2:
            precondition(modal1Presented)
            modal2Presented = true
            return nil
        }
    }
}

extension State: Equatable {
    static func ==(lhs: State, rhs: State) -> Bool {
        return lhs.modal1Presented == rhs.modal1Presented && lhs.modal2Presented == rhs.modal2Presented
    }
}

protocol Reducer {
    associatedtype Message
    mutating func send(_ message: Message) -> Command<Message>?
}

class Driver<S> where S: Equatable, S: Reducer {
    let state: Input<S>
    private(set) var rootViewController: IBox<UIViewController>!

    var viewController: UIViewController {
        return rootViewController.unbox
    }

    init(initial: S, view: (I<S>, @escaping (S.Message) -> ()) -> IBox<UIViewController>) {
        state = Input(initial)
        rootViewController = view(state.i, { [weak self] msg in
            self?.send(msg)
        })
    }

    func send(_ message: S.Message) {
        self.state.change { x in
            if let command = x.send(message) {
                //                switch command {
                //                }
            }
        }
    }
}

// TODO: move to incremental+UIKit
public func viewController<V: UIView>(rootView: IBox<V>, constraints: [Constraint] = [], modalChild: I<IBox<UIViewController>?> = I(constant: nil)) -> IBox<UIViewController> {
    let vc = UIViewController()
    let box = IBox(vc)
    vc.view.addSubview(rootView.unbox)
    vc.view.backgroundColor = .white
    box.disposables.append(rootView)
    rootView.unbox.translatesAutoresizingMaskIntoConstraints = false
    for c in constraints {
        c(vc.view, rootView.unbox).isActive = true
    }
    box.bindModalChild(to: modalChild)
    return box
}

public extension IBox where V: UIViewController {

    public func bindModalChild(to value: I<IBox<UIViewController>?>) {
        self.disposables.append(value.observe { child in
            guard let child = child else {
                if let _ = self.unbox.presentedViewController {
                    self.unbox.dismiss(animated: true)
                }
                return
            }
            self.unbox.present(child.unbox, animated: true)
            self.disposables.append(child)
        })
    }
}


func view(state: I<State>, send: @escaping (State.Message) -> ()) -> IBox<UIViewController> {
    let loading = activityIndicator(style: I(constant: .gray), animating: I(constant: true))
    let modal1Input = Input<IBox<UIViewController>?>(eq: { $0 == $1 }, nil)

    let empty = viewController(rootView: loading, constraints: [equalCenterX(), equalCenterY()], modalChild: modal1Input.i)
    let rootView = I(constant: empty)
    let vcs = flatten([rootView])
    let nc = navigationController(vcs)
    nc.disposables.append(state[\.modal1Presented].observe { presented in
        print("modal1presented", presented)
        if presented {
            let modal2Input = Input<IBox<UIViewController>?>(eq: { $0 == $1 }, nil)
            let label1 = label(text: I(constant: "modal1"))
            let modal1 = viewController(rootView: label1, modalChild: modal2Input.i)
            modal1.disposables.append(state[\.modal2Presented].observe { presented2 in
                print("modal2presented", presented2)
                if presented2 {
                    let label2 = label(text: I(constant: "modal2"))
                    modal2Input.write(viewController(rootView: label2))
                } else {
                    modal2Input.write(nil)
                }

            })
            modal1Input.write(modal1)
        } else {
            modal1Input.write(nil)
        }

    })

    return nc.map { $0 }
}


let driver = Driver<State>(initial: State(modal1Presented: false, modal2Presented: false), view: view)


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
//    var mapViewController: ViewController?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
//        mapViewController = ViewController()
//        window?.rootViewController = mapViewController
        window?.rootViewController = driver.viewController
        window?.makeKeyAndVisible()

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            driver.send(.present1)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1100)) {
            driver.send(.present2)
        }


//        DispatchQueue(label: "Track Loading").async {
//            let tracks = self.loadTracks()
//            DispatchQueue.main.async {
//                self.mapViewController?.setTracks(tracks)
//            }
//        }
        application.applicationSupportsShakeToEdit = true
        return true
    }
    
    func loadTracks() -> [Track] {
        let definitions: [(Color, Int)] = [
            (.red, 4),
            (.turquoise, 5),
            (.brightGreen, 7),
            (.beige, 2),
            (.green, 4),
            (.purple, 3),
            (.violet, 4),
            (.blue, 3),
            (.brown, 4),
            (.yellow, 4),
            (.gray, 0),
            (.lightBlue, 4),
            (.lightBrown, 5),
            (.orange, 0),
            (.pink, 4),
            (.lightPink, 6)
        ]
        var allTracks: [[Track]] = []
        time {
            allTracks = definitions.map { (color, count) in
                let trackNames: [(Int, String)] = (0...count).map { ($0, "wabe \(color.name)-strecke \($0)") }
                return trackNames.map { numberAndName -> Track in
                    let reader = TrackReader(url: Bundle.main.url(forResource: numberAndName.1, withExtension: "gpx")!)!
                    return Track(color: color, number: numberAndName.0, name: reader.name, points: reader.points)
                }
            }
        }
        return Array(allTracks.joined())
    }
}

