//
//  SettingsViewController.swift
//  PIA VPN
//
//  Created by Davide De Rosa on 12/8/17.
//  Copyright © 2017 London Trust Media. All rights reserved.
//

import UIKit
import PIALibrary
import PIATunnel
import SafariServices
import SwiftyBeaver

private let log = SwiftyBeaver.self

private extension String {
    var vpnTypeDescription: String {
        guard (self != PIATunnelProfile.vpnType) else {
            return "OpenVPN"
        }
        return self
    }
}

class SettingsViewController: AutolayoutViewController {
    private enum Section: Int {
        case connection

        case encryption

        case applicationSettings
        
        case contentBlocker

        case applicationInformation
        
        case reset

        case development
    }

    private enum Setting: Int {
        case vpnProtocolSelection

        case vpnSocket
        
        case vpnPort

        case encryptionCipher

        case encryptionDigest
        
        case encryptionHandshake
        
        case automaticReconnection

        case contentBlockerState
        
        case contentBlockerRefreshRules

        case mace
        
        case darkTheme

        case sendDebugLog
        
        case resetSettings
        
        // development
        
//        case truncateDebugLog
//
//        case recalculatePingTimes
//
//        case invokeMACERequest
        
        case resolveGoogleAdsDomain
    }
    
    private static let allSections: [Section] = [
        .connection,
        .encryption,
        .applicationSettings,
        .contentBlocker,
        .applicationInformation,
        .reset
    ]

    private var visibleSections: [Section] = []

    private var rowsBySection: [Section: [Setting]] = [
        .connection: [
            .vpnProtocolSelection,
            .vpnSocket,
            .vpnPort
        ],
        .encryption: [
            .encryptionCipher,
            .encryptionDigest,
            .encryptionHandshake
        ],
        .applicationSettings: [], // dynamic
        .contentBlocker: [
            .contentBlockerState,
            .contentBlockerRefreshRules
        ],
        .applicationInformation: [
            .sendDebugLog
        ],
        .reset: [
            .resetSettings
        ],
        .development: [
//            .truncateDebugLog,
//            .recalculatePingTimes,
//            .invokeMACERequest,
            .mace,
            .resolveGoogleAdsDomain
        ]
    ]
    
    private struct Cells {
        static let setting = "SettingCell"
    }
    
    @IBOutlet private weak var tableView: UITableView!

    private lazy var switchPersistent = UISwitch()
    
    private lazy var switchMACE = UISwitch()
    
    private lazy var switchContentBlocker = FakeSwitch()
    
    private lazy var switchDarkMode = UISwitch()
    
    private lazy var imvSelectedOption = UIImageView(image: Asset.accessorySelected.image)

    private var isContentBlockerEnabled = false

    private var isTransitioningTheme = false

//    private lazy var buttonConfirm = UIBarButtonItem(
//        barButtonSystemItem: .save,
//        target: self,
//        action: #selector(confirmChangesImmediately(_:))
//    )
    
    private var pendingPreferences = Client.preferences.editable()

    private var pendingVPNAction: VPNAction?
//    private var pendingVPNAction: VPNAction? {
//        didSet {
//            if let _ = pendingVPNAction {
//                buttonConfirm.isEnabled = true
//            } else {
//                buttonConfirm.isEnabled = false
//            }
//        }
//    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
        title = L10n.Menu.Item.settings

//        buttonConfirm.isEnabled = false
//        navigationItem.rightBarButtonItem = buttonConfirm

        if #available(iOS 11, *) {
            tableView.sectionFooterHeight = UITableViewAutomaticDimension
            tableView.estimatedSectionFooterHeight = 1.0
        }
        switchPersistent.addTarget(self, action: #selector(togglePersistentConnection(_:)), for: .valueChanged)
        switchMACE.addTarget(self, action: #selector(toggleMACE(_:)), for: .valueChanged)
        switchContentBlocker.addTarget(self, action: #selector(showContentBlockerTutorial), for: .touchUpInside)
        switchDarkMode.addTarget(self, action: #selector(toggleDarkMode(_:)), for: .valueChanged)
        redisplaySettings()

        NotificationCenter.default.addObserver(self, selector: #selector(refreshContentBlockerState), name: .UIApplicationDidBecomeActive, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        refreshContentBlockerState()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if #available(iOS 11, *) {
            tableView.reloadData()
        }
    }
    
    // MARK: Actions
    
    @objc private func togglePersistentConnection(_ sender: UISwitch) {
        pendingPreferences.isPersistentConnection = sender.isOn
        redisplaySettings()
        reportUpdatedPreferences()
    }
    
    @objc private func toggleMACE(_ sender: UISwitch) {
        pendingPreferences.mace = sender.isOn
        redisplaySettings()
        reportUpdatedPreferences()
    }

    // XXX: no need to bufferize app preferences
    @objc private func toggleDarkMode(_ sender: UISwitch) {
        transitionTheme(to: sender.isOn ? .dark : .light)
    }
    
    @objc private func showContentBlockerTutorial() {
        perform(segue: StoryboardSegue.Main.contentBlockerSegueIdentifier)
    }

    @objc private func refreshContentBlockerState(withHUD: Bool = false) {
        if #available(iOS 10, *) {
            var hud: HUD?
            if withHUD {
                hud = HUD()
            }
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: AppConstants.Extensions.adBlockerBundleIdentifier) { (state, error) in
                DispatchQueue.main.async {
                    hud?.hide()
                    
                    self.isContentBlockerEnabled = state?.isEnabled ?? false
                    self.redisplaySettings()
                }
            }
        }
    }
    
    private func refreshContentBlockerRules() {
        let hud = HUD()
        SFContentBlockerManager.reloadContentBlocker(withIdentifier: AppConstants.Extensions.adBlockerBundleIdentifier) { (error) in
            if let error = error {
                log.error("Could not reload Safari Content Blocker: \(error)")
            }
            DispatchQueue.main.async {
                hud.hide()
            }
        }
    }
    
    private func submitTunnelLog() {
        let hud = HUD()
        
        Client.providers.vpnProvider.submitLog { (log, error) in
            hud.hide()
            
            let title: String
            let message: String
        
            defer {
                let alert = Macros.alert(title, message)
                alert.addCancelAction(L10n.Global.ok)
                self.present(alert, animated: true, completion: nil)
                
//                UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[log] applicationActivities:nil];
//                [self presentViewController:vc animated:YES completion:NULL];
            }
            
            guard let log = log else {
                title = L10n.Settings.ApplicationInformation.Debug.Failure.title
                message = L10n.Settings.ApplicationInformation.Debug.Failure.message
                return
            }
            guard !log.isEmpty else {
                title = L10n.Settings.ApplicationInformation.Debug.Empty.title
                message = L10n.Settings.ApplicationInformation.Debug.Empty.message
                return
            }

            title = L10n.Settings.ApplicationInformation.Debug.Success.title
            message = L10n.Settings.ApplicationInformation.Debug.Success.message(log.identifier)
        }
    }
    
    private func resetToDefaultSettings() {
        let alert = Macros.alert(
            L10n.Settings.Reset.Defaults.Confirm.title,
            L10n.Settings.Reset.Defaults.Confirm.message
        )
        alert.addDestructiveAction(L10n.Settings.Reset.Defaults.Confirm.button) {
            self.doReset()
        }
        alert.addCancelAction(L10n.Global.cancel)
        self.present(alert, animated: true, completion: nil)
    }
    
    private func doReset() {

        // only don't reset selected server
        let savedServer = pendingPreferences.preferredServer
        pendingPreferences.reset()
        pendingPreferences.preferredServer = savedServer

        transitionTheme(to: .light)

        redisplaySettings()
        reportUpdatedPreferences()
    }
    
//    @IBAction private func confirmChangesImmediately(_ sender: Any?) {
//        confirmChanges(retainingConnection: false) {
//            self.buttonConfirm.isEnabled = false
//        }
//    }
    
    func commitChanges(_ completionHandler: @escaping () -> Void) {
        if !enablesMACE() && !visibleSections.contains(.development) {
            pendingPreferences.mace = false
        }
        
        guard let action = pendingVPNAction else {
            pendingPreferences.commit()
            completionHandler()
            return
        }
        
        let isDisconnected = (Client.providers.vpnProvider.vpnStatus == .disconnected)
        let completionHandlerAfterVPNAction: (Bool) -> Void = { (shouldReconnect) in
            let hud = HUD()
            action.execute { (error) in
                self.pendingVPNAction = nil
                
                if shouldReconnect && !isDisconnected {
                    Client.providers.vpnProvider.reconnect(after: nil) { (error) in
                        completionHandler()
                        hud.hide()
                    }
                } else {
                    completionHandler()
                    hud.hide()
                }
            }
        }

        // disconnected, commit and execute
        guard !isDisconnected else {
            pendingPreferences.commit()
            completionHandlerAfterVPNAction(false)
            return
        }

        // must reconnect
        guard action.canRetainConnection else {
            let alert = Macros.alert(
                title,
                L10n.Settings.Commit.Messages.mustDisconnect
            )

            // reconnect -> reconnect VPN and close
            alert.addDefaultAction(L10n.Settings.Commit.Buttons.reconnect) {
                self.pendingPreferences.commit()
                completionHandlerAfterVPNAction(true)
            }

            // cancel -> revert changes and close
            alert.addAction(UIAlertAction(title: L10n.Global.cancel, style: .cancel) { (action) in
                completionHandler()
            })
            present(alert, animated: true, completion: nil)
            return
        }

        // should reconnect
        guard !pendingPreferences.suggestsVPNReconnection() else {
            pendingPreferences.commit()
            
            let alert = Macros.alert(
                title,
                L10n.Settings.Commit.Messages.shouldReconnect
            )

            // reconnect -> reconnect VPN and close
            alert.addDefaultAction(L10n.Settings.Commit.Buttons.reconnect) {
                completionHandlerAfterVPNAction(true)
            }

            // later -> close
            alert.addAction(UIAlertAction(title: L10n.Settings.Commit.Buttons.later, style: .cancel) { (action) in
                completionHandler()
            })
            present(alert, animated: true, completion: nil)
            return
        }
        
        // action doesn't affect VPN connection, commit and execute
        pendingPreferences.commit()
        completionHandlerAfterVPNAction(false)
    }
    
    // MARK: Unwind segues
    
    @IBAction private func unwoundContentBlockerViewController(_ segue: UIStoryboardSegue) {
    }

    // MARK: Development
    
//    private func truncateDebugLog() {
//        connectionBusiness.truncateTunnelSnapshot()
//    }
    
//    private func recalculatePingTimes() {
//        PingerDaemon.shared.pingAllRegions()
//    }
    
//    private func invokeMACERequest() {
//        PIAEphemeralClient.shared()!.enableMACE(nil)
//    }
    
    private func resolveGoogleAdsDomain() {
        let resolver = DNSResolver(hostname: "google-analytics.com")
        resolver.resolve { (entries, error) in
            let addresses: [String]
            if let entries = entries, !entries.isEmpty {
                addresses = entries
            } else {
                addresses = ["Can't resolve"]
            }
            
            let alert = Macros.alert(nil, addresses.joined(separator: ","))
            alert.addCancelAction("Close")
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    // MARK: Helpers
    
    private func enablesMACE() -> Bool {
        return Flags.shared.enablesMACE(withVPNType: pendingPreferences.vpnType)
    }

    @objc private func redisplaySettings() {
        var sections = SettingsViewController.allSections
        if !Flags.shared.enablesProtocolSelection {
            sections.remove(at: sections.index(of: .connection)!)
            sections.remove(at: sections.index(of: .encryption)!)
        } else {
            if (pendingPreferences.vpnType == IPSecProfile.vpnType) {
                sections.remove(at: sections.index(of: .encryption)!)
            }
        }
        if enablesMACE() {
            rowsBySection[.applicationSettings] = [
                .automaticReconnection,
                .darkTheme,
                .mace
            ]
            sections.remove(at: sections.index(of: .contentBlocker)!)
        } else {
            rowsBySection[.applicationSettings] = [
                .automaticReconnection,
                .darkTheme
            ]
        }
        if (pendingPreferences.vpnType != PIATunnelProfile.vpnType) {
            sections.remove(at: sections.index(of: .applicationInformation)!)
        }
        if !Flags.shared.enablesResetSettings {
            sections.remove(at: sections.index(of: .reset)!)
        }
        if Flags.shared.enablesDevelopmentSettings {
            sections.append(.development)
        }
        visibleSections = sections
        
        if (pendingPreferences.vpnType == PIATunnelProfile.vpnType) {
            rowsBySection[.connection] = [
                .vpnProtocolSelection,
                .vpnSocket,
                .vpnPort
            ]
        } else {
            rowsBySection[.connection] = [
                .vpnProtocolSelection
            ]
        }
        
        tableView.reloadData()
    }
    
    private func reportUpdatedPreferences() {
        pendingVPNAction = pendingPreferences.requiredVPNAction()
    }
    
    private func currentOpenVPNConfiguration() -> PIATunnelProvider.Configuration {
        guard let configuration = pendingPreferences.vpnCustomConfiguration(for: PIATunnelProfile.vpnType) as? PIATunnelProvider.Configuration else {
            fatalError("No default VPN custom configuration provided for PIA protocol")
        }
        return configuration
    }
    
    private func transitionTheme(to code: ThemeCode) {
        guard !isTransitioningTheme else {
            return
        }
        guard (code != AppPreferences.shared.currentThemeCode) else {
            return
        }

        AppPreferences.shared.currentThemeCode = code
        guard let window = UIApplication.shared.windows.first else {
            fatalError("No window?")
        }
        isTransitioningTheme = true
        UIView.animate(withDuration: AppConfiguration.Animations.duration, animations: {
            window.alpha = 0.0
        }, completion: { (success) in
            code.apply(theme: Theme.current, reload: true)
            
            UIView.animate(withDuration: AppConfiguration.Animations.duration) {
                window.alpha = 1.0
                self.isTransitioningTheme = false
            }
        })
    }
    
    // MARK: ModalController
    
    override func dismissModal() {
        commitChanges {
            super.dismissModal()
        }
    }
    
    // MARK: Restylable
    
    override func viewShouldRestyle() {
        super.viewShouldRestyle()
    
        // XXX: for some reason, UITableView is not affected by appearance updates
        if let viewContainer = viewContainer {
            Theme.current.applyLightBackground(viewContainer)
        }
        Theme.current.applyLightBackground(tableView)
        Theme.current.applyDividerToSeparator(tableView)
        tableView.reloadData()
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return visibleSections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch visibleSections[section] {
        case .connection:
            return L10n.Settings.Connection.title
            
        case .encryption:
            return L10n.Settings.Encryption.title
            
        case .applicationSettings:
            return L10n.Settings.ApplicationSettings.title
            
        case .contentBlocker:
            return L10n.Settings.ContentBlocker.title

        case .applicationInformation:
            return L10n.Settings.ApplicationInformation.title

        case .reset:
            return L10n.Settings.Reset.title

        case .development:
            return "DEVELOPMENT"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch visibleSections[section] {
        case .applicationSettings:
            var footer: [String] = []
            if !pendingPreferences.isPersistentConnection {
                footer.append(L10n.Settings.ApplicationSettings.Persistent.Footer.disabled)
            }
            if enablesMACE() {
                footer.append(L10n.Settings.ApplicationSettings.Mace.footer)
            }
            return footer.joined(separator: "\n\n")
            
        case .contentBlocker:
            return L10n.Settings.ContentBlocker.footer

        default:
            break
        }
        
        return nil
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rowsBySection[visibleSections[section]]!.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Cells.setting, for: indexPath)
        cell.accessoryType = .disclosureIndicator
        cell.accessoryView = nil
        cell.selectionStyle = .default

        let section = visibleSections[indexPath.section]
        guard let setting = rowsBySection[section]?[indexPath.row] else {
            fatalError("Data source is incorrect")
        }
        
        switch setting {
        case .vpnProtocolSelection:
            cell.textLabel?.text = L10n.Settings.Connection.VpnProtocol.title
            cell.detailTextLabel?.text = pendingPreferences.vpnType.vpnTypeDescription
            if !Flags.shared.enablesProtocolSelection {
                cell.accessoryType = .none
                cell.selectionStyle = .none
            }

        case .vpnSocket:
            cell.textLabel?.text = L10n.Settings.Connection.SocketProtocol.title
            cell.detailTextLabel?.text = "UDP" // TODO: hardcoded
            cell.accessoryType = .none
            cell.selectionStyle = .none
            
        case .vpnPort:
            cell.textLabel?.text = L10n.Settings.Connection.RemotePort.title
            cell.detailTextLabel?.text = pendingPreferences.preferredPort?.description ?? L10n.Global.automatic
            if !Flags.shared.enablesRemotePortSetting {
                cell.detailTextLabel?.text = Client.providers.serverProvider.targetServer.bestOpenVPNAddressForUDP?.port.description
                cell.accessoryType = .none
                cell.selectionStyle = .none
            }

        case .encryptionCipher:
            let configuration = currentOpenVPNConfiguration()
            cell.textLabel?.text = L10n.Settings.Encryption.Cipher.title
            cell.detailTextLabel?.text = configuration.cipher.description
            if !Flags.shared.enablesEncryptionSettings {
                cell.accessoryType = .none
                cell.selectionStyle = .none
            }
            
        case .encryptionDigest:
            let configuration = currentOpenVPNConfiguration()
            cell.textLabel?.text = L10n.Settings.Encryption.Digest.title
            cell.detailTextLabel?.text = configuration.digest.description
            if !Flags.shared.enablesEncryptionSettings {
                cell.accessoryType = .none
                cell.selectionStyle = .none
            }

        case .encryptionHandshake:
            let configuration = currentOpenVPNConfiguration()
            cell.textLabel?.text = L10n.Settings.Encryption.Handshake.title
            cell.detailTextLabel?.text = configuration.handshake.description
            if !Flags.shared.enablesEncryptionSettings {
                cell.accessoryType = .none
                cell.selectionStyle = .none
            }

        case .automaticReconnection:
            cell.textLabel?.text = L10n.Settings.ApplicationSettings.Persistent.title
            cell.detailTextLabel?.text = nil
            cell.accessoryView = switchPersistent
            cell.selectionStyle = .none
            switchPersistent.isOn = pendingPreferences.isPersistentConnection
            
        case .mace:
            cell.textLabel?.text = L10n.Settings.ApplicationSettings.Mace.title
            cell.detailTextLabel?.text = nil
            cell.accessoryView = switchMACE
            cell.selectionStyle = .none
            switchMACE.isOn = pendingPreferences.mace
            
        case .contentBlockerState:
            cell.textLabel?.text = L10n.Settings.ContentBlocker.State.title
            cell.detailTextLabel?.text = nil
            if #available(iOS 10, *) {
                cell.accessoryView = switchContentBlocker
                cell.selectionStyle = .none
                switchContentBlocker.isOn = isContentBlockerEnabled
            }
            
        case .contentBlockerRefreshRules:
            cell.textLabel?.text = L10n.Settings.ContentBlocker.Refresh.title
            cell.detailTextLabel?.text = nil
            
        case .darkTheme:
            cell.textLabel?.text = L10n.Settings.ApplicationSettings.DarkTheme.title
            cell.detailTextLabel?.text = nil
            cell.accessoryView = switchDarkMode
            cell.selectionStyle = .none
            switchDarkMode.isOn = (AppPreferences.shared.currentThemeCode == .dark)

        case .sendDebugLog:
            cell.textLabel?.text = L10n.Settings.ApplicationInformation.Debug.title
            cell.detailTextLabel?.text = nil
            
        case .resetSettings:
            cell.textLabel?.text = L10n.Settings.Reset.Defaults.title
            cell.detailTextLabel?.text = nil

//        case .truncateDebugLog:
//            cell.textLabel?.text = "Truncate debug log (disconnect first)"
//            cell.detailTextLabel?.text = nil
//
//        case .recalculatePingTimes:
//            cell.textLabel?.text = "Recalculate ping times (disconnect first)"
//            cell.detailTextLabel?.text = nil
//
//        case .invokeMACERequest:
//            cell.textLabel?.text = "Invoke MACE request"
//            cell.detailTextLabel?.text = nil

        case .resolveGoogleAdsDomain:
            cell.textLabel?.text = "Resolve google-analytics.com"
            cell.detailTextLabel?.text = nil
        }

        Theme.current.applySolidLightBackground(cell)
        Theme.current.applyDetailTableCell(cell)

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = visibleSections[indexPath.section]
        guard let setting = rowsBySection[section]?[indexPath.row] else {
            fatalError("Data source is incorrect")
        }

        var controller: OptionsViewController?
        
        switch setting {
        case .vpnProtocolSelection:
            let options: [String] = [
                IPSecProfile.vpnType,
                PIATunnelProfile.vpnType
            ]
            controller = OptionsViewController()
            controller?.options = options
            controller?.selectedOption = pendingPreferences.vpnType
            
        case .vpnPort:
            guard Flags.shared.enablesRemotePortSetting else {
                break
            }
            var options = Client.providers.serverProvider.currentServersConfiguration.vpnPorts.udp
            options.insert(0, at: 0)
            controller = OptionsViewController()
            controller?.options = options
            controller?.selectedOption = pendingPreferences.preferredPort ?? 0

        case .encryptionCipher:
            guard Flags.shared.enablesEncryptionSettings else {
                break
            }
            let configuration = currentOpenVPNConfiguration()
            let options: [PIATunnelProvider.Cipher] = [
                .aes128cbc,
                .aes256cbc
            ]
            controller = OptionsViewController()
            controller?.options = options.map { $0.rawValue }
            controller?.selectedOption = configuration.cipher.rawValue

        case .encryptionDigest:
            guard Flags.shared.enablesEncryptionSettings else {
                break
            }
            let configuration = currentOpenVPNConfiguration()
            let options: [PIATunnelProvider.Digest] = [
                .sha1,
                .sha256
            ]
            controller = OptionsViewController()
            controller?.options = options.map { $0.rawValue }
            controller?.selectedOption = configuration.digest.rawValue

        case .encryptionHandshake:
            guard Flags.shared.enablesEncryptionSettings else {
                break
            }
            let configuration = currentOpenVPNConfiguration()
            let options: [PIATunnelProvider.Handshake] = [
                .rsa2048,
                .rsa3072,
                .rsa4096,
                .ecc256r1,
                .ecc521r1
            ]
            controller = OptionsViewController()
            controller?.options = options.map { $0.rawValue }
            controller?.selectedOption = configuration.handshake.rawValue
            
        case .contentBlockerState:
            if #available(iOS 10, *) {
                
            } else {
                showContentBlockerTutorial()
            }
            
        case .contentBlockerRefreshRules:
            refreshContentBlockerRules()

        case .sendDebugLog:
            submitTunnelLog()
            
        case .resetSettings:
            resetToDefaultSettings()

//        case .truncateDebugLog:
//            truncateDebugLog()
//
//        case .recalculatePingTimes:
//            recalculatePingTimes()
//
//        case .invokeMACERequest:
//            invokeMACERequest()

        case .resolveGoogleAdsDomain:
            resolveGoogleAdsDomain()

        default:
            break
        }

        if let controller = controller {
            guard let cell = tableView.cellForRow(at: indexPath) else {
                fatalError("Cell not found at \(indexPath)")
            }

            controller.title = cell.textLabel?.text
            controller.tag = setting.rawValue
            controller.delegate = self

            parent?.navigationItem.setEmptyBackButton()
            navigationController?.pushViewController(controller, animated: true)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        Theme.current.applyTableSectionHeader(view)
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        Theme.current.applyTableSectionFooter(view)
    }
}

extension SettingsViewController: OptionsViewControllerDelegate {
    func backgroundColorForOptionsController(_ controller: OptionsViewController) -> UIColor {
        return Theme.current.palette.lightBackground
    }
    
    func tableStyleForOptionsController(_ controller: OptionsViewController) -> UITableViewStyle {
        return .grouped
    }
    
    func optionsController(_ controller: OptionsViewController, didLoad tableView: UITableView) {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.cellLayoutMarginsFollowReadableWidth = false
    }

    func optionsController(_ controller: OptionsViewController, tableView: UITableView, reusableCellAt indexPath: IndexPath) -> UITableViewCell {
        return tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
    }
    
    func optionsController(_ controller: OptionsViewController, renderOption option: AnyHashable, in cell: UITableViewCell, at row: Int, isSelected: Bool) {
        guard let setting = Setting(rawValue: controller.tag) else {
            fatalError("Unhandled setting \(controller.tag)")
        }

        switch setting {
        case .vpnProtocolSelection:
            cell.textLabel?.text = (option as? String)?.vpnTypeDescription
            
        case .vpnPort:
            if let port = option as? UInt16, (port > 0) {
                cell.textLabel?.text = (option as? UInt16)?.description
            } else {
                cell.textLabel?.text = L10n.Global.automatic
            }

        case .encryptionCipher:
            cell.textLabel?.text = PIATunnelProvider.Cipher(rawValue: option as! String)?.description

        case .encryptionDigest:
            cell.textLabel?.text = PIATunnelProvider.Digest(rawValue: option as! String)?.description

        case .encryptionHandshake:
            cell.textLabel?.text = PIATunnelProvider.Handshake(rawValue: option as! String)?.description

        default:
            break
        }
        
        cell.accessoryView = (isSelected ? imvSelectedOption : nil)

        Theme.current.applySolidLightBackground(cell)
        Theme.current.applyDetailTableCell(cell)
    }

    func optionsController(_ controller: OptionsViewController, didSelectOption option: AnyHashable, at row: Int) {
        guard let setting = Setting(rawValue: controller.tag) else {
            fatalError("Unhandled setting \(controller.tag)")
        }

        var vpnHasChanged = false
        var newVPNType: String?
        var newPort: UInt16?
        var newConfiguration: PIATunnelProvider.Configuration?

        switch setting {
        case .vpnProtocolSelection:
            newVPNType = option as? String
            vpnHasChanged = (newVPNType != pendingPreferences.vpnType)
            
        case .vpnPort:
            newPort = option as? UInt16
            vpnHasChanged = (newPort != pendingPreferences.preferredPort)

        case .encryptionCipher:
            let configuration = currentOpenVPNConfiguration()
            var newBuilder = configuration.builder()
            newBuilder.cipher = PIATunnelProvider.Cipher(rawValue: option as! String)!
            newConfiguration = newBuilder.build()
            vpnHasChanged = (newConfiguration != configuration)

        case .encryptionDigest:
            let configuration = currentOpenVPNConfiguration()
            var newBuilder = configuration.builder()
            newBuilder.digest = PIATunnelProvider.Digest(rawValue: option as! String)!
            newConfiguration = newBuilder.build()
            vpnHasChanged = (newConfiguration != configuration)

        case .encryptionHandshake:
            let configuration = currentOpenVPNConfiguration()
            var newBuilder = configuration.builder()
            newBuilder.handshake = PIATunnelProvider.Handshake(rawValue: option as! String)!
            newConfiguration = newBuilder.build()
            vpnHasChanged = (newConfiguration != configuration)

        default:
            break
        }
        
        if vpnHasChanged {
            if let vpnType = newVPNType {
                pendingPreferences.vpnType = vpnType
            }
            if let port = newPort, (port > 0) {
                pendingPreferences.preferredPort = port
            } else {
                pendingPreferences.preferredPort = nil
            }
            if let configuration = newConfiguration {
                let activeType = newVPNType ?? pendingPreferences.vpnType
                pendingPreferences.setVPNCustomConfiguration(configuration, for: activeType)
            }
        }

        redisplaySettings()
        navigationController?.popViewController(animated: true)
        reportUpdatedPreferences()
    }
}