//: [Previous](@previous)
import Foundation
import Incremental
import UIKit

enum Command<Message> {
}

struct State: Reducer {
    private(set) var modal1Presented: Bool
    private(set) var modal2Presented: Bool
    
    enum Message {
        case present1
        case present2
        case dismiss1
        case dismiss2
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
        case .dismiss1:
            modal1Presented = false
            modal2Presented = false
            return nil
        case .dismiss2:
            modal2Presented = false
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

// TODO: move
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

public extension IBox where V: UIViewController {

    public func bindModalChild(to value: I<IBox<UIViewController>?>) {
        self.disposables.append(value.observe { child in
            guard let child = child else {
                //getting rid of the if (i.e. always calling dismiss) doesnt help
                if let _ = self.unbox.presentedViewController {
                    self.unbox.dismiss(animated: true) //I think its also possible to call dismiss on the child. Im not sure if that would help (probably not), but the child is no longer accessible here. I would need some equivalent of `combinePrevious` from ReactiveSwift (doable with flatMap?) or restructure the code to handle the dismissal somewhere where the child is still accessible.
                }
                return
            }
            self.unbox.present(child.unbox, animated: true)
            self.disposables.append(child)
        })
    }
}


import PlaygroundSupport
let driver = Driver<State>(initial: State(modal1Presented: false, modal2Presented: false), view: view)
PlaygroundPage.current.liveView = driver.viewController

//UIKit seem to handle this just fine. I thought it used to complain about "simulataneous transitions", but now it just does them sequentially. Case where .present2 is delayed 0.1seconds also works fine.
driver.send(.present1)
driver.send(.present2)


//DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1000)) { //works
DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { //modal2 stays presented (presentations didnt finish in time for dismissal, see bindModalChild above)
//DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { // looks like its not even determistic :( this worked for me once.
    driver.send(.dismiss2)
}

print("✅")

