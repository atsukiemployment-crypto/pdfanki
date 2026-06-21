import Foundation
import Capacitor
import PencilKit
import UIKit

/// 学習中の1問(全ページを縦結合した巻物)をPencilKitの全画面で開くプラグイン。
/// 上部バーに採点ボタン(正解/不正解/スキップ)を載せ、書きながらそのまま採点まで完結する。
/// - 指: 上下の慣性スクロールで全ページを連続移動、ピンチでズーム(0.5〜5倍)
/// - Apple Pencil: 描画専用(パームリジェクション)+ Apple純正ツールパレット
///
/// Webからの呼び出し:
///   Capacitor.Plugins.PencilKitPlugin.open({ background, label, title, count })
/// 返り値:
///   { action: "correct" | "wrong" | "skip" | "exit", image: <base64 PNG> }
@objc(PencilKitPlugin)
public class PencilKitPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "PencilKitPlugin"
    public let jsName = "PencilKitPlugin"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "close", returnType: CAPPluginReturnPromise)
    ]

    @objc func open(_ call: CAPPluginCall) {
        guard let bgString = call.getString("background"),
              let bgData = Data(base64Encoded: bgString),
              let bgImage = UIImage(data: bgData) else {
            call.reject("background (base64 image) is required")
            return
        }
        let label = call.getString("label") ?? ""
        let title = call.getString("title") ?? ""
        let count = call.getString("count") ?? ""
        let priority = call.getString("priority") ?? ""
        let difficulty = call.getString("difficulty") ?? ""

        DispatchQueue.main.async {
            guard #available(iOS 14.0, *) else {
                call.reject("この機能はiOS 14以降が必要です")
                return
            }
            guard let bridgeVC = self.bridge?.viewController else {
                call.reject("no view controller")
                return
            }
            let vc = PencilDrawViewController(background: bgImage, label: label, title: title, count: count, priority: priority, difficulty: difficulty)
            vc.modalPresentationStyle = .fullScreen
            vc.onFinish = { action, drawingImage in
                var ret: [String: Any] = ["action": action]
                if let img = drawingImage, let png = img.pngData() {
                    ret["image"] = png.base64EncodedString()
                }
                call.resolve(ret)
            }
            if let presented = bridgeVC.presentedViewController as? PencilDrawViewController {
                presented.replace(with: vc)
            } else {
                bridgeVC.present(vc, animated: true)
            }
        }
    }

    @objc func close(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard #available(iOS 14.0, *) else {
                call.resolve()
                return
            }
            if let presented = self.bridge?.viewController?.presentedViewController as? PencilDrawViewController {
                presented.dismiss(animated: true)
            }
            call.resolve()
        }
    }
}

@available(iOS 14.0, *)
final class PencilDrawViewController: UIViewController, UIScrollViewDelegate {
    private var backgroundImage: UIImage
    private var labelText: String
    private var titleText: String
    private var countText: String
    private var priorityText: String
    private var difficultyText: String

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let imageView = UIImageView()
    private let canvasView = PKCanvasView()
    private let topBar = UIView()
    private let infoLabel = UILabel()
    private let priBadge = UILabel()
    private let difBadge = UILabel()
    private var toolPicker: PKToolPicker?
    private var lastArea = CGRect.zero
    var onFinish: ((String, UIImage?) -> Void)?
    private var finished = false

    init(background: UIImage, label: String, title: String, count: String, priority: String = "", difficulty: String = "") {
        self.backgroundImage = background
        self.labelText = label
        self.titleText = title
        self.countText = count
        self.priorityText = priority
        self.difficultyText = difficulty
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGray6

        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.5
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        imageView.image = backgroundImage
        imageView.contentMode = .scaleToFill
        contentView.addSubview(imageView)

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .pencilOnly
        canvasView.isScrollEnabled = false
        canvasView.drawing = PKDrawing()   // 新規画面は必ず白紙から始める（書き込み残り防止）
        contentView.addSubview(canvasView)

        topBar.backgroundColor = .secondarySystemBackground
        view.addSubview(topBar)
        buildTopBar()
    }

    private func buildTopBar() {
        let exitButton = UIButton(type: .system)
        exitButton.setTitle("✕ 閉じる", for: .normal)
        exitButton.tintColor = .label
        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)

        infoLabel.font = .systemFont(ofSize: 13, weight: .medium)
        infoLabel.textColor = .secondaryLabel
        infoLabel.textAlignment = .center
        infoLabel.lineBreakMode = .byTruncatingTail

        setupBadge(priBadge)
        setupBadge(difBadge)
        updateInfoLabel()

        let skipButton = makeChip(title: "スキップ", bg: .tertiarySystemFill, fg: .secondaryLabel)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        let wrongButton = makeChip(title: "✗ 不正解", bg: UIColor.systemRed.withAlphaComponent(0.15), fg: .systemRed)
        wrongButton.addTarget(self, action: #selector(wrongTapped), for: .touchUpInside)
        let correctButton = makeChip(title: "✓ 正解", bg: UIColor.systemGreen.withAlphaComponent(0.15), fg: .systemGreen)
        correctButton.addTarget(self, action: #selector(correctTapped), for: .touchUpInside)

        let rightStack = UIStackView(arrangedSubviews: [skipButton, wrongButton, correctButton])
        rightStack.axis = .horizontal
        rightStack.spacing = 8

        // 中央: バッジ(重要度/難易度) + 問題情報 を横並びに
        let centerStack = UIStackView(arrangedSubviews: [priBadge, difBadge, infoLabel])
        centerStack.axis = .horizontal
        centerStack.spacing = 6
        centerStack.alignment = .center

        for v in [exitButton, centerStack, rightStack] {
            v.translatesAutoresizingMaskIntoConstraints = false
            topBar.addSubview(v)
        }
        NSLayoutConstraint.activate([
            exitButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            exitButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -9),
            rightStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            rightStack.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -7),
            centerStack.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: rightStack.centerYAnchor),
            centerStack.leadingAnchor.constraint(greaterThanOrEqualTo: exitButton.trailingAnchor, constant: 8),
            centerStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),
        ])
    }

    private func setupBadge(_ b: UILabel) {
        b.font = .systemFont(ofSize: 11, weight: .bold)
        b.textAlignment = .center
        b.layer.cornerRadius = 5
        b.layer.masksToBounds = true
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    // A=赤 / B=橙 / C=緑 の色を返す
    private func gradeColor(_ g: String) -> UIColor {
        switch g {
        case "A": return .systemRed
        case "B": return .systemOrange
        case "C": return .systemGreen
        default:  return .systemGray
        }
    }

    private func styleBadge(_ b: UILabel, prefix: String, grade: String) {
        if grade.isEmpty { b.isHidden = true; return }
        b.isHidden = false
        b.text = "  \(prefix)\(grade)  "
        let c = gradeColor(grade)
        b.textColor = c
        b.backgroundColor = c.withAlphaComponent(0.15)
    }

    private func updateInfoLabel() {
        let parts = [countText, labelText, titleText].filter { !$0.isEmpty }
        infoLabel.text = parts.joined(separator: "  ")
        styleBadge(priBadge, prefix: "重", grade: priorityText)
        styleBadge(difBadge, prefix: "難", grade: difficultyText)
    }

    private func makeChip(title: String, bg: UIColor, fg: UIColor) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.setTitleColor(fg, for: .normal)
        b.backgroundColor = bg
        b.layer.cornerRadius = 9
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        return b
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        let barHeight: CGFloat = safe.top + 52
        topBar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: barHeight)

        let area = CGRect(
            x: safe.left,
            y: barHeight,
            width: view.bounds.width - safe.left - safe.right,
            height: view.bounds.height - barHeight - safe.bottom
        )
        guard area != lastArea else { return }
        lastArea = area

        scrollView.frame = area
        scrollView.zoomScale = 1.0

        let imgSize = backgroundImage.size
        let scale = area.width / imgSize.width
        contentView.frame = CGRect(x: 0, y: 0, width: area.width, height: imgSize.height * scale)
        imageView.frame = contentView.bounds
        canvasView.frame = contentView.bounds
        scrollView.contentSize = contentView.frame.size
        centerContent()
        // ツールパレットや描画レイヤーがボタンの上に重なってタップを奪うのを防ぐため、
        // 採点バーを常に最前面に固定する。
        view.bringSubviewToFront(topBar)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showToolPicker()
        // ツールパレット表示後にボタンが隠れないよう最前面へ
        view.bringSubviewToFront(topBar)
    }

    private func showToolPicker() {
        let picker = PKToolPicker()
        picker.setVisible(true, forFirstResponder: canvasView)
        picker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        toolPicker = picker
    }

    /// 問題から問題への遷移: 画面を閉じずに中身だけ差し替える
    func replace(with next: PencilDrawViewController) {
        self.onFinish = next.onFinish
        self.backgroundImage = next.backgroundImage
        self.imageView.image = next.backgroundImage
        self.labelText = next.labelText
        self.titleText = next.titleText
        self.countText = next.countText
        self.priorityText = next.priorityText
        self.difficultyText = next.difficultyText
        updateInfoLabel()
        self.canvasView.drawing = PKDrawing()
        self.finished = false
        self.lastArea = .zero
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
        self.scrollView.setContentOffset(.zero, animated: false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }
    private func centerContent() {
        let b = scrollView.bounds.size
        let c = scrollView.contentSize
        let ox = max((b.width - c.width) / 2, 0)
        let oy = max((b.height - c.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: oy, left: ox, bottom: oy, right: ox)
    }

    private func renderDrawing() -> UIImage {
        let bounds = canvasView.bounds
        let pixelWidth = backgroundImage.size.width * backgroundImage.scale
        let renderScale = bounds.width > 0 ? pixelWidth / bounds.width : 1
        return canvasView.drawing.image(from: bounds, scale: renderScale)
    }

    @objc private func correctTapped() { finish(action: "correct") }
    @objc private func wrongTapped()   { finish(action: "wrong") }
    @objc private func skipTapped()    { finish(action: "skip") }
    @objc private func exitTapped()    { finish(action: "exit") }

    private func finish(action: String) {
        guard !finished else { return }
        finished = true
        onFinish?(action, renderDrawing())
    }
}
