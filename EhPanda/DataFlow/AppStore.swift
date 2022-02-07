//
//  AppStore.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 3/12/25.
//

import SwiftUI
import ComposableArchitecture

struct AppState: Equatable {
    var appDelegateState = AppDelegateState()
    var appRouteState = AppRouteState()
    var appLockState = AppLockState()
    var tabBarState = TabBarState()
    var homeState = HomeState()
    var favoritesState = FavoritesState()
    var searchRootState = SearchRootState()
    var settingState = SettingState()
}

enum AppAction: BindableAction {
    case binding(BindingAction<AppState>)
    case onScenePhaseChange(ScenePhase)

    case appDelegate(AppDelegateAction)
    case appRoute(AppRouteAction)
    case appLock(AppLockAction)

    case tabBar(TabBarAction)

    case home(HomeAction)
    case favorites(FavoritesAction)
    case searchRoot(SearchRootAction)
    case setting(SettingAction)
}

struct AnyEnvironment {}
struct AppEnvironment {
    let dfClient: DFClient
    let urlClient: URLClient
    let fileClient: FileClient
    let imageClient: ImageClient
    let deviceClient: DeviceClient
    let loggerClient: LoggerClient
    let hapticClient: HapticClient
    let libraryClient: LibraryClient
    let cookiesClient: CookiesClient
    let databaseClient: DatabaseClient
    let clipboardClient: ClipboardClient
    let appDelegateClient: AppDelegateClient
    let userDefaultsClient: UserDefaultsClient
    let uiApplicationClient: UIApplicationClient
    let authorizationClient: AuthorizationClient
}

let appReducerCore = Reducer<AppState, AppAction, AppEnvironment> { state, action, environment in
    switch action {
    case .binding(\.appRouteState.$route):
        return state.appRouteState.route == nil ? .init(value: .appRoute(.clearSubStates)) : .none

    case .binding(\.settingState.$setting):
        return .init(value: .setting(.syncSetting))

    case .binding(\.settingState.$searchFilter):
        state.settingState.searchFilter.fixInvalidData()
        return .init(value: .setting(.syncSearchFilter))

    case .binding(\.settingState.$globalFilter):
        state.settingState.globalFilter.fixInvalidData()
        return .init(value: .setting(.syncGlobalFilter))

    case .binding(\.settingState.$watchedFilter):
        state.settingState.watchedFilter.fixInvalidData()
        return .init(value: .setting(.syncWatchedFilter))

    case .binding:
        return .none

    case .onScenePhaseChange(let scenePhase):
        switch scenePhase {
        case .active:
            let threshold = state.settingState.setting.autoLockPolicy.rawValue
            let blurRadius = state.settingState.setting.backgroundBlurRadius
            var effects: [Effect<AppAction, Never>] = [
                .init(value: .setting(.fetchGreeting)),
                .init(value: .appLock(.onBecomeActive(threshold, blurRadius)))
            ]
            if threshold < 0, state.settingState.setting.detectsLinksFromClipboard {
                effects.append(.init(value: .appRoute(.detectClipboardURL)))
            }
            return .merge(effects)
        case .inactive:
            let blurRadius = state.settingState.setting.backgroundBlurRadius
            return .init(value: .appLock(.onBecomeInactive(blurRadius)))
        default:
            break
        }
        return .none

    case .appDelegate(.migration(.onDatabasePreparationSuccess)):
        return .init(value: .setting(.loadUserSettings))

    case .appDelegate:
        return .none

    case .appRoute(.clearSubStates):
        var effects = [Effect<AppAction, Never>]()
        if environment.deviceClient.isPad() {
            state.settingState.route = nil
            effects.append(.init(value: .setting(.clearSubStates)))
        }
        return effects.isEmpty ? .none : .merge(effects)

    case .appRoute(.filters(.onResetFilterConfirmed)):
        return .init(value: .setting(.resetFilter(state.appRouteState.filtersState.filterRange)))

    case .appRoute(.searchRequest(.fetchGalleries)):
        state.appRouteState.searchRequestState.filter = state.settingState.searchFilter
        return .none

    case .appRoute(.searchRequest(.onFiltersButtonTapped)), .home(.frontpage(.onFiltersButtonTapped)),
            .home(.popular(.onFiltersButtonTapped)), .home(.watched(.onFiltersButtonTapped)),
            .searchRoot(.onFiltersButtonTapped), .searchRoot(.searchRequest(.onFiltersButtonTapped)):
        return .init(value: .appRoute(.setNavigation(.filters)))

    case .appRoute:
        return .none

    case .appLock(.authorizeDone(let isSucceeded)):
        return isSucceeded && state.settingState.setting.detectsLinksFromClipboard
        ? .init(value: .appRoute(.detectClipboardURL)) : .none

    case .appLock:
        return .none

    case .tabBar(.setTabBarItemType(let type)):
        var effects = [Effect<AppAction, Never>]()
        if type == state.tabBarState.tabBarItemType {
            switch type {
            case .home:
                effects.append(.init(value: .home(.fetchAllGalleries)))
            case .favorites:
                effects.append(.init(value: .favorites(.fetchGalleries())))
            case .search:
                effects.append(.init(value: .searchRoot(.fetchDatabaseInfos)))
            case .setting:
                break
            }
            if [.home, .favorites, .search].contains(type) {
                effects.append(environment.hapticClient.generateFeedback(.soft).fireAndForget())
            }
        }
        if type == .setting && environment.deviceClient.isPad() {
            effects.append(.init(value: .appRoute(.setNavigation(.setting))))
        }
        return effects.isEmpty ? .none : .merge(effects)

    case .tabBar:
        return .none

    case .home(.frontpage(.fetchGalleries)), .home(.frontpage(.fetchMoreGalleries)):
        state.homeState.frontpageState.filter = state.settingState.globalFilter
        return .none

    case .home(.popular(.fetchGalleries)):
        state.homeState.popularState.filter = state.settingState.globalFilter
        return .none

    case .home(.watched(.fetchGalleries)), .home(.watched(.fetchMoreGalleries)):
        state.homeState.watchedState.filter = state.settingState.watchedFilter
        return .none

    case .home(.fetchPopularGalleries), .home(.fetchFrontpageGalleries):
        state.homeState.filter = state.settingState.globalFilter
        return .none

    case .home(.watched(.onNotLoginViewButtonTapped)), .favorites(.onNotLoginViewButtonTapped):
        var effects: [Effect<AppAction, Never>] = [
            environment.hapticClient.generateFeedback(.soft).fireAndForget(),
            .init(value: .tabBar(.setTabBarItemType(.setting)))
        ]
        effects.append(.init(value: .setting(.setNavigation(.account))))
        if !environment.cookiesClient.didLogin {
            effects.append(
                .init(value: .setting(.account(.setNavigation(.login))))
                    .delay(for: .milliseconds(200), scheduler: DispatchQueue.main).eraseToEffect()
            )
        }
        return .merge(effects)

    case .home:
        return .none

    case .favorites:
        return .none

    case .searchRoot(.searchRequest(.fetchGalleries)):
        state.searchRootState.searchRequestState.filter = state.settingState.searchFilter
        return .none

    case .searchRoot:
        return .none

    case .setting(.fetchGreetingDone(let result)):
        return .init(value: .appRoute(.fetchGreetingDone(result)))

    case .setting:
        return .none
    }
}
.binding()

let appReducer = Reducer<AppState, AppAction, AppEnvironment>.combine(
    appReducerCore,
    appRouteReducer.pullback(
        state: \.appRouteState,
        action: /AppAction.appRoute,
        environment: {
            .init(
                dfClient: $0.dfClient,
                urlClient: $0.urlClient,
                fileClient: $0.fileClient,
                imageClient: $0.imageClient,
                deviceClient: $0.deviceClient,
                loggerClient: $0.loggerClient,
                hapticClient: $0.hapticClient,
                libraryClient: $0.libraryClient,
                cookiesClient: $0.cookiesClient,
                databaseClient: $0.databaseClient,
                clipboardClient: $0.clipboardClient,
                appDelegateClient: $0.appDelegateClient,
                userDefaultsClient: $0.userDefaultsClient,
                uiApplicationClient: $0.uiApplicationClient,
                authorizationClient: $0.authorizationClient
            )
        }
    ),
    appLockReducer.pullback(
        state: \.appLockState,
        action: /AppAction.appLock,
        environment: {
            .init(
                authorizationClient: $0.authorizationClient
            )
        }
    ),
    appDelegateReducer.pullback(
        state: \.self,
        action: /AppAction.appDelegate,
        environment: {
            .init(
                dfClient: $0.dfClient,
                libraryClient: $0.libraryClient,
                cookiesClient: $0.cookiesClient,
                databaseClient: $0.databaseClient
            )
        }
    ),
    tabBarReducer.pullback(
        state: \.tabBarState,
        action: /AppAction.tabBar,
        environment: {
            .init(
                deviceClient: $0.deviceClient
            )
        }
    ),
    homeReducer.pullback(
        state: \.homeState,
        action: /AppAction.home,
        environment: {
            .init(
                urlClient: $0.urlClient,
                fileClient: $0.fileClient,
                imageClient: $0.imageClient,
                deviceClient: $0.deviceClient,
                hapticClient: $0.hapticClient,
                libraryClient: $0.libraryClient,
                cookiesClient: $0.cookiesClient,
                databaseClient: $0.databaseClient,
                clipboardClient: $0.clipboardClient,
                appDelegateClient: $0.appDelegateClient,
                uiApplicationClient: $0.uiApplicationClient
            )
        }
    ),
    favoritesReducer.pullback(
        state: \.favoritesState,
        action: /AppAction.favorites,
        environment: {
            .init(
                urlClient: $0.urlClient,
                fileClient: $0.fileClient,
                imageClient: $0.imageClient,
                deviceClient: $0.deviceClient,
                hapticClient: $0.hapticClient,
                cookiesClient: $0.cookiesClient,
                databaseClient: $0.databaseClient,
                clipboardClient: $0.clipboardClient,
                appDelegateClient: $0.appDelegateClient,
                uiApplicationClient: $0.uiApplicationClient
            )
        }
    ),
    searchRootReducer.pullback(
        state: \.searchRootState,
        action: /AppAction.searchRoot,
        environment: {
            .init(
                urlClient: $0.urlClient,
                fileClient: $0.fileClient,
                imageClient: $0.imageClient,
                deviceClient: $0.deviceClient,
                hapticClient: $0.hapticClient,
                cookiesClient: $0.cookiesClient,
                databaseClient: $0.databaseClient,
                clipboardClient: $0.clipboardClient,
                appDelegateClient: $0.appDelegateClient,
                uiApplicationClient: $0.uiApplicationClient
            )
        }
    ),
    settingReducer.pullback(
        state: \.settingState,
        action: /AppAction.setting,
        environment: {
            .init(
                dfClient: $0.dfClient,
                fileClient: $0.fileClient,
                deviceClient: $0.deviceClient,
                loggerClient: $0.loggerClient,
                hapticClient: $0.hapticClient,
                libraryClient: $0.libraryClient,
                cookiesClient: $0.cookiesClient,
                databaseClient: $0.databaseClient,
                clipboardClient: $0.clipboardClient,
                appDelegateClient: $0.appDelegateClient,
                userDefaultsClient: $0.userDefaultsClient,
                uiApplicationClient: $0.uiApplicationClient,
                authorizationClient: $0.authorizationClient
            )
        }
    )
)
.logging()
