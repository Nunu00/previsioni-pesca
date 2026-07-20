import re

filepath = r"c:\Antigravity\meteopesca\previsioni-pesca-android\app\src\main\java\com\vincenzo\previsionipesca\MainActivity.kt"

with open(filepath, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Fix imports
old_imports = """import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVGrid
import androidx.compose.foundation.lazy.grid.items"""

new_imports = """import androidx.compose.ui.geometry.Size
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch"""

content = content.replace(old_imports, new_imports)

# 2. Add coroutine scope helper at the beginning of MainScreen
old_mainscreen = """@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen() {
    var selectedLocation by remember { mutableStateOf(TideEngine.stations[0]) }"""

new_mainscreen = """@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen() {
    val scope = rememberCoroutineScope()
    var selectedLocation by remember { mutableStateOf(TideEngine.stations[0]) }"""

content = content.replace(old_mainscreen, new_mainscreen)

# 3. Fix location.latitude / longitude to location.coordinate.latitude / longitude
content = content.replace("selectedLocation.latitude", "selectedLocation.coordinate.latitude")
content = content.replace("selectedLocation.longitude", "selectedLocation.coordinate.longitude")

# 4. Fix onRefresh launch block
old_refresh = """                onRefresh = {
                    isFetchingWeather = true
                    weatherErrorMessage = null
                    val job = kotlinx.coroutines.GlobalScope.run {
                        kotlinx.coroutines.launch {
                            try {
                                val cache = WeatherService.fetch7DayWeather(selectedLocation.coordinate.latitude, selectedLocation.coordinate.longitude)
                                weatherCache = cache
                                isFetchingWeather = false
                            } catch (e: Exception) {
                                weatherErrorMessage = "Impossibile caricare il meteo."
                                isFetchingWeather = false
                            }
                        }
                    }
                }"""

new_refresh = """                onRefresh = {
                    isFetchingWeather = true
                    weatherErrorMessage = null
                    scope.launch {
                        try {
                            val cache = WeatherService.fetch7DayWeather(selectedLocation.coordinate.latitude, selectedLocation.coordinate.longitude)
                            weatherCache = cache
                            isFetchingWeather = false
                        } catch (e: Exception) {
                            weatherErrorMessage = "Impossibile caricare il meteo."
                            isFetchingWeather = false
                        }
                    }
                }"""

content = content.replace(old_refresh, new_refresh)

# 5. Fix Coeff. Marea line
old_coeff = """AstroItem(label = "🎚️ Coeff. Marea", value = "${forecast.tideCoeffFactor.let { max(20, min(120, (70.0 + 30.0 * cos(4.0 * Math.PI * (forecast.moonAge / 29.53059)) + ( (406700.0 - forecast.moonAntiTransit?.let { 384400.0 } /*approx*/ ?: 384400.0) / 50300.0 - 0.5 ) * 30.0)).toInt() }}")"""
new_coeff = """AstroItem(label = "🎚️ Coeff. Marea", value = "${forecast.tideCoeffFactor.toInt()}")"""

# Let's do a substring replacement since spacing/formatting can differ
# Find lines matching "Coeff. Marea"
content = re.sub(r'AstroItem\(label = "🎚️ Coeff\. Marea", value = ".*"\)', new_coeff, content)

with open(filepath, "w", encoding="utf-8") as f:
    f.write(content)

print("MainActivity fixes completed successfully!")
