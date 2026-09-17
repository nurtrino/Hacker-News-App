package com.nurtrino.hackernews

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.padding
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.nurtrino.hackernews.data.FeedsViewModel
import com.nurtrino.hackernews.data.Library
import com.nurtrino.hackernews.data.LobstersThreadViewModel
import com.nurtrino.hackernews.data.LobstersViewModel
import com.nurtrino.hackernews.data.SearchViewModel
import com.nurtrino.hackernews.data.Settings
import com.nurtrino.hackernews.data.ThreadViewModel
import com.nurtrino.hackernews.data.UserViewModel
import com.nurtrino.hackernews.net.Http
import com.nurtrino.hackernews.ui.FeedScreen
import com.nurtrino.hackernews.ui.HackerNewsTheme
import com.nurtrino.hackernews.ui.LobstersScreen
import com.nurtrino.hackernews.ui.LobstersStoryScreen
import com.nurtrino.hackernews.ui.SavedScreen
import com.nurtrino.hackernews.ui.SearchScreen
import com.nurtrino.hackernews.ui.SettingsScreen
import com.nurtrino.hackernews.ui.StoryScreen
import com.nurtrino.hackernews.ui.UserScreen

class MainActivity : ComponentActivity() {

    private lateinit var settings: Settings
    private lateinit var library: Library

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        Http.init(applicationContext)
        settings = Settings(applicationContext)
        library = Library(applicationContext)

        setContent {
            HackerNewsTheme(settings.appearance, settings.textScale) {
                Root(settings, library)
            }
        }
    }

    override fun onStop() {
        super.onStop()
        // Persist immediately rather than waiting out the debounce.
        if (::library.isInitialized) library.flush()
    }
}

private sealed class Tab(val route: String, val label: String) {
    data object Stories : Tab("stories", "Stories")
    data object Lobsters : Tab("lobsters", "Lobsters")
    data object Search : Tab("search", "Search")
    data object Saved : Tab("saved", "Saved")
    data object SettingsTab : Tab("settings", "Settings")
}

private val TABS = listOf(Tab.Stories, Tab.Lobsters, Tab.Search, Tab.Saved, Tab.SettingsTab)

@Composable
private fun Root(settings: Settings, library: Library) {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    // Activity-scoped so switching tabs keeps feed state and search results.
    val feeds: FeedsViewModel = viewModel()
    val lobsters: LobstersViewModel = viewModel()
    val search: SearchViewModel = viewModel()

    Scaffold(
        bottomBar = {
            if (currentRoute in TABS.map { it.route }) {
                NavigationBar {
                    TABS.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = {
                                if (currentRoute != tab.route) {
                                    navController.navigate(tab.route) {
                                        popUpTo(Tab.Stories.route) { saveState = true }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                }
                            },
                            icon = { Icon(iconFor(tab), contentDescription = tab.label) },
                            label = { Text(tab.label) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Tab.Stories.route,
            modifier = Modifier.padding(padding),
        ) {
            composable(Tab.Stories.route) {
                FeedScreen(feeds, settings, library) { navController.navigate("story/$it") }
            }
            composable(Tab.Lobsters.route) {
                LobstersScreen(lobsters, settings, library) { navController.navigate("lobsters/$it") }
            }
            composable(Tab.Search.route) {
                SearchScreen(search, settings, library) { navController.navigate("story/$it") }
            }
            composable(Tab.Saved.route) {
                SavedScreen(settings, library) { navController.navigate("story/$it") }
            }
            composable(Tab.SettingsTab.route) {
                SettingsScreen(settings, library)
            }
            composable(
                route = "story/{id}",
                arguments = listOf(navArgument("id") { type = NavType.IntType }),
            ) { entry ->
                val id = entry.arguments?.getInt("id") ?: return@composable
                val model: ThreadViewModel = viewModel(
                    key = "story-$id",
                    factory = simpleFactory { ThreadViewModel(id) },
                )
                StoryScreen(
                    model = model,
                    settings = settings,
                    library = library,
                    onBack = { navController.popBackStack() },
                    onOpenUser = { navController.navigate("user/$it") },
                )
            }
            composable(
                route = "lobsters/{id}",
                arguments = listOf(navArgument("id") { type = NavType.StringType }),
            ) { entry ->
                val id = entry.arguments?.getString("id") ?: return@composable
                val model: LobstersThreadViewModel = viewModel(
                    key = "lobsters-$id",
                    factory = simpleFactory { LobstersThreadViewModel(id, lobsters.story(id)) },
                )
                LobstersStoryScreen(
                    model = model,
                    settings = settings,
                    onBack = { navController.popBackStack() },
                )
            }
            composable(
                route = "user/{name}",
                arguments = listOf(navArgument("name") { type = NavType.StringType }),
            ) { entry ->
                val name = entry.arguments?.getString("name") ?: return@composable
                val model: UserViewModel = viewModel(
                    key = "user-$name",
                    factory = simpleFactory { UserViewModel(name) },
                )
                UserScreen(
                    username = name,
                    model = model,
                    settings = settings,
                    library = library,
                    onBack = { navController.popBackStack() },
                    onOpenStory = { navController.navigate("story/$it") },
                )
            }
        }
    }
}

private fun iconFor(tab: Tab) = when (tab) {
    Tab.Stories -> Icons.Filled.Home
    Tab.Lobsters -> Icons.Filled.List
    Tab.Search -> Icons.Filled.Search
    Tab.Saved -> Icons.Filled.Star
    Tab.SettingsTab -> Icons.Filled.Settings
}

/** Minimal factory so screen-scoped ViewModels can take constructor arguments. */
private fun <T : ViewModel> simpleFactory(builder: () -> T) = object : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <VM : ViewModel> create(modelClass: Class<VM>): VM = builder() as VM
}
