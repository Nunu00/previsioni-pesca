package com.vincenzo.previsionipesca

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.ui.geometry.Size
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vincenzo.previsionipesca.engine.*
import com.vincenzo.previsionipesca.models.*
import com.vincenzo.previsionipesca.ui.theme.*
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            PrevisioniPescaTheme {
                MainApp()
            }
        }
    }
}

// Global cache to prevent UI lags
private val activityCache = mutableMapOf<String, ActivityLevel>()

fun activityForDate(
    date: Date,
    location: Location,
    weatherCache: Map<String, FetchedWeatherData>
): ActivityLevel {
    val cal = Calendar.getInstance().apply { time = date }
    val dateKey = String.format("%04d-%02d-%02d", cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))

    val hasWeather = weatherCache[dateKey] != null
    val cacheKey = "${location.name}_${dateKey}_${if (hasWeather) "w" else "c"}"

    val cached = activityCache[cacheKey]
    if (cached != null) return cached

    val coord = location.coordinate
    val astro = AstronomyEngine.calculateAstronomy(date, coord)
    val tides = TideEngine.calculateDailyTides(date, coord)

    var sst = 20.0
    var cloud = 20.0
    var wind = 0.0
    var swell = 0.2
    var delta = 0.0
    var windSpeed = 4.0

    val cachedWeather = weatherCache[dateKey]
    if (cachedWeather != null) {
        cloud = cachedWeather.cloudCover
        wind = cachedWeather.windDirectionChange
        swell = cachedWeather.swellHeight
        delta = cachedWeather.surfaceTempDelta24h
        sst = cachedWeather.waterTemp
        windSpeed = cachedWeather.windSpeedMps
    } else {
        val today = Date()
        val todayCal = Calendar.getInstance().apply { time = today }
        val diffDays = ((date.time - today.time) / 86400000).toInt()
        val seasonalWaterTemp = climatologicalMean(date)

        if (diffDays < -1) {
            sst = seasonalWaterTemp
        } else {
            val todayKey = String.format("%04d-%02d-%02d", todayCal.get(Calendar.YEAR), todayCal.get(Calendar.MONTH) + 1, todayCal.get(Calendar.DAY_OF_MONTH))
            val currentSst = weatherCache[todayKey]?.waterTemp ?: 20.0

            val day7Cal = Calendar.getInstance().apply {
                time = today
                add(Calendar.DAY_OF_MONTH, 7)
            }
            val day7Key = String.format("%04d-%02d-%02d", day7Cal.get(Calendar.YEAR), day7Cal.get(Calendar.MONTH) + 1, day7Cal.get(Calendar.DAY_OF_MONTH))
            val day7SST = weatherCache[day7Key]?.waterTemp ?: currentSst
            val day7Climatology = climatologicalMean(day7Cal.time)
            val anomalyAtDay7 = day7SST - day7Climatology

            val daysAhead = (diffDays - 7).toDouble()
            val tau = decorrelationTime(date)
            val decayFactor = exp(-daysAhead / tau)
            sst = seasonalWaterTemp + anomalyAtDay7 * decayFactor
        }
    }

    val weatherFactor = WeatherFactor(
        cloudCoverPercent = cloud,
        windDirectionChange = wind,
        swellHeight = swell,
        surfaceTempDelta24h = delta,
        windSpeedMps = windSpeed
    )

    val forecastResult = RulesEngine.evaluateForecast(
        date = date,
        location = location,
        sunrise = astro.sunrise,
        sunset = astro.sunset,
        moonrise = astro.moonrise,
        moonset = astro.moonset,
        moonTransit = astro.moonTransit,
        moonAntiTransit = astro.moonAntiTransit,
        moonAge = astro.moonAge,
        tides = tides,
        weather = weatherFactor,
        waterTempCelsius = sst
    )

    val level = forecastResult.dailyActivity
    activityCache[cacheKey] = level
    return level
}

private fun climatologicalMean(date: Date): Double {
    val cal = Calendar.getInstance().apply { time = date }
    val dayOfYear = cal.get(Calendar.DAY_OF_YEAR)
    // Sine wave modeling Mediterranean water temps: Min = 13.0°C in mid-Feb, Max = 25.5°C in mid-Aug
    val mean = 19.25
    val amplitude = 6.25
    val phaseLag = 135.0 // peak shifted to day 227 (August 15th)
    return mean + amplitude * sin(2.0 * Math.PI * (dayOfYear - phaseLag) / 365.0)
}

private fun decorrelationTime(date: Date): Double {
    val cal = Calendar.getInstance().apply { time = date }
    val month = cal.get(Calendar.MONTH)
    // Shorter memory in transition periods (spring/autumn) due to storms: 10 days; stable summer: 18 days
    return if (month in 5..8) 18.0 else 10.0
}

@Composable
fun MainApp() {
    var isSplashActive by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        delay(2000)
        isSplashActive = false
    }

    Crossfade(targetState = isSplashActive, label = "splashTransition") { showSplash ->
        if (showSplash) {
            SplashScreen()
        } else {
            MainScreen()
        }
    }
}

@Composable
fun SplashScreen() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(MidnightBlue, DeepBlue)
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        VStack(
            horizontalAlignment = Alignment.CenterHorizontally,
            spacing = 24
        ) {
            Box(contentAlignment = Alignment.Center) {
                // Outer glowing circle
                Box(
                    modifier = Modifier
                        .size(110.dp)
                        .clip(CircleShape)
                        .background(TealAccent.copy(alpha = 0.15f))
                )
                // Inside circular logo container
                Box(
                    modifier = Modifier
                        .size(80.dp)
                        .clip(CircleShape)
                        .background(DarkNavy)
                        .border(1.dp, TealAccent.copy(alpha = 0.4f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "🐟",
                        fontSize = 36.sp,
                        textAlign = TextAlign.Center
                    )
                }
            }

            VStack(
                horizontalAlignment = Alignment.CenterHorizontally,
                spacing = 8
            ) {
                Text(
                    text = "Previsioni Pesca",
                    color = Color.White,
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 1.sp
                )
                Text(
                    text = "Il tuo compagno di pesca scientifico",
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            CircularProgressIndicator(
                color = TealAccent,
                modifier = Modifier.size(28.dp),
                strokeWidth = 3.dp
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen() {
    val scope = rememberCoroutineScope()
    var selectedLocation by remember { mutableStateOf(TideEngine.stations[0]) }
    var selectedDate by remember { mutableStateOf(Date()) }
    var weatherCache by remember { mutableStateOf<Map<String, FetchedWeatherData>>(emptyMap()) }
    var isFetchingWeather by remember { mutableStateOf(false) }
    var weatherErrorMessage by remember { mutableStateOf<String?>(null) }

    // Current environmental conditions
    var cloudCover by remember { mutableStateOf(20.0) }
    var windDirectionChange by remember { mutableStateOf(10.0) }
    var swellHeight by remember { mutableStateOf(0.2) }
    var surfaceTempDelta24h by remember { mutableStateOf(0.0) }
    var waterTempCelsius by remember { mutableStateOf(20.0) }
    var windSpeedMps by remember { mutableStateOf(4.0) }

    val cal = Calendar.getInstance().apply { time = selectedDate }
    val dateKey = String.format("%04d-%02d-%02d", cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))

    // LaunchedEffect to automatically load weather when location changes
    LaunchedEffect(selectedLocation) {
        isFetchingWeather = true
        weatherErrorMessage = null
        try {
            val cache = WeatherService.fetch7DayWeather(selectedLocation.coordinate.latitude, selectedLocation.coordinate.longitude)
            weatherCache = cache
            isFetchingWeather = false
        } catch (e: Exception) {
            e.printStackTrace()
            weatherErrorMessage = "Meteo offline: impossibile caricare le previsioni."
            isFetchingWeather = false
        }
    }

    // Evaluate current environmental variables based on selected date and weather cache
    LaunchedEffect(selectedDate, weatherCache) {
        val cached = weatherCache[dateKey]
        if (cached != null) {
            cloudCover = cached.cloudCover
            windDirectionChange = cached.windDirectionChange
            swellHeight = cached.swellHeight
            surfaceTempDelta24h = cached.surfaceTempDelta24h
            waterTempCelsius = cached.waterTemp
            windSpeedMps = cached.windSpeedMps
        } else {
            cloudCover = 20.0
            windDirectionChange = 0.0
            swellHeight = 0.2
            surfaceTempDelta24h = 0.0
            windSpeedMps = 4.0

            val today = Date()
            val diffDays = ((selectedDate.time - today.time) / 86400000).toInt()
            val seasonalWaterTemp = climatologicalMean(selectedDate)

            if (diffDays < -1) {
                waterTempCelsius = seasonalWaterTemp
            } else {
                val todayCal = Calendar.getInstance().apply { time = today }
                val todayKey = String.format("%04d-%02d-%02d", todayCal.get(Calendar.YEAR), todayCal.get(Calendar.MONTH) + 1, todayCal.get(Calendar.DAY_OF_MONTH))
                val currentSst = weatherCache[todayKey]?.waterTemp ?: 20.0

                val day7Cal = Calendar.getInstance().apply {
                    time = today
                    add(Calendar.DAY_OF_MONTH, 7)
                }
                val day7Key = String.format("%04d-%02d-%02d", day7Cal.get(Calendar.YEAR), day7Cal.get(Calendar.MONTH) + 1, day7Cal.get(Calendar.DAY_OF_MONTH))
                val day7SST = weatherCache[day7Key]?.waterTemp ?: currentSst
                val day7Climatology = climatologicalMean(day7Cal.time)
                val anomalyAtDay7 = day7SST - day7Climatology

                val daysAhead = (diffDays - 7).toDouble()
                val tau = decorrelationTime(selectedDate)
                val decayFactor = exp(-daysAhead / tau)
                waterTempCelsius = seasonalWaterTemp + anomalyAtDay7 * decayFactor
            }
        }
    }

    // Recalculate daily forecast
    val currentForecast = remember(selectedDate, selectedLocation, cloudCover, windDirectionChange, swellHeight, surfaceTempDelta24h, waterTempCelsius, windSpeedMps) {
        val coord = selectedLocation.coordinate
        val astro = AstronomyEngine.calculateAstronomy(selectedDate, coord)
        val tides = TideEngine.calculateDailyTides(selectedDate, coord)

        val weatherFactor = WeatherFactor(
            cloudCoverPercent = cloudCover,
            windDirectionChange = windDirectionChange,
            swellHeight = swellHeight,
            surfaceTempDelta24h = surfaceTempDelta24h,
            windSpeedMps = windSpeedMps
        )

        RulesEngine.evaluateForecast(
            date = selectedDate,
            location = selectedLocation,
            sunrise = astro.sunrise,
            sunset = astro.sunset,
            moonrise = astro.moonrise,
            moonset = astro.moonset,
            moonTransit = astro.moonTransit,
            moonAntiTransit = astro.moonAntiTransit,
            moonAge = astro.moonAge,
            tides = tides,
            weather = weatherFactor,
            waterTempCelsius = waterTempCelsius
        )
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    VStack(horizontalAlignment = Alignment.CenterHorizontally, spacing = 2) {
                        Text(
                            text = "Previsioni Pesca",
                            color = Color.White,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = SimpleDateFormat("EEEE d MMMM", Locale.ITALIAN).format(selectedDate).replaceFirstChar { it.uppercase() },
                            color = TealAccent,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                    containerColor = MidnightBlue
                )
            )
        },
        containerColor = MidnightBlue
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .verticalScroll(rememberScrollState())
                .padding(bottom = 24.dp)
        ) {
            // Location picker
            LocationPickerCard(
                selectedLocation = selectedLocation,
                onLocationSelected = {
                    selectedLocation = it
                    activityCache.clear() // Clear cache when changing location
                }
            )

            // Calendar Card
            CalendarCard(
                selectedDate = selectedDate,
                onDateSelected = { selectedDate = it },
                selectedLocation = selectedLocation,
                weatherCache = weatherCache
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Daily activity summary
            DailyActivitySummaryCard(forecast = currentForecast)

            Spacer(modifier = Modifier.height(16.dp))

            // Best windows card
            BestWindowsCard(forecast = currentForecast)

            Spacer(modifier = Modifier.height(16.dp))

            // Tide Chart
            TideChartCard(forecast = currentForecast, selectedDate = selectedDate)

            Spacer(modifier = Modifier.height(16.dp))

            // Marine and Coastal Parameters
            CoastalParametersCard(
                cloudCover = cloudCover,
                windDirectionChange = windDirectionChange,
                swellHeight = swellHeight,
                surfaceTempDelta24h = surfaceTempDelta24h,
                windSpeedMps = windSpeedMps,
                isFetching = isFetchingWeather,
                errorMessage = weatherErrorMessage,
                onRefresh = {
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
                }
            )
        }
    }
}

@Composable
fun LocationPickerCard(
    selectedLocation: Location,
    onLocationSelected: (Location) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(containerColor = DarkNavy),
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.08f))
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = true }
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(text = "📍", fontSize = 18.sp)
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Località",
                    color = Color.White.copy(alpha = 0.8f),
                    fontSize = 14.sp
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = selectedLocation.name,
                    color = TealAccent,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text(text = "▼", color = TealAccent, fontSize = 10.sp)
            }

            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
                modifier = Modifier.background(DeepBlue)
            ) {
                TideEngine.stations.forEach { loc ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                text = loc.name,
                                color = if (loc.name == selectedLocation.name) TealAccent else Color.White
                            )
                        },
                        onClick = {
                            onLocationSelected(loc)
                            expanded = false
                        }
                    )
                }
            }
        }
    }
}

@Composable
fun CalendarCard(
    selectedDate: Date,
    onDateSelected: (Date) -> Unit,
    selectedLocation: Location,
    weatherCache: Map<String, FetchedWeatherData>
) {
    var currentMonthDate by remember { mutableStateOf(Date()) }
    val calendar = Calendar.getInstance()

    // Determine current month calendar grid
    val days = remember(currentMonthDate) {
        val cal = Calendar.getInstance().apply { time = currentMonthDate }
        cal.set(Calendar.DAY_OF_MONTH, 1)
        val startOfMonth = cal.time

        val maxDay = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
        val dayList = mutableListOf<Date>()
        for (i in 1..maxDay) {
            val c = Calendar.getInstance().apply {
                time = startOfMonth
                set(Calendar.DAY_OF_MONTH, i)
            }
            dayList.add(c.time)
        }
        dayList
    }

    val leadingEmptySlots = remember(currentMonthDate) {
        val cal = Calendar.getInstance().apply {
            time = currentMonthDate
            set(Calendar.DAY_OF_MONTH, 1)
        }
        // Day of week (1 is Sunday, 2 is Monday...)
        val dayOfWeek = cal.get(Calendar.DAY_OF_WEEK)
        // Convert to offset where Monday is 0
        when (dayOfWeek) {
            Calendar.MONDAY -> 0
            Calendar.TUESDAY -> 1
            Calendar.WEDNESDAY -> 2
            Calendar.THURSDAY -> 3
            Calendar.FRIDAY -> 4
            Calendar.SATURDAY -> 5
            Calendar.SUNDAY -> 6
            else -> 0
        }
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(containerColor = DarkNavy),
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.08f))
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Month Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = {
                    val c = Calendar.getInstance().apply {
                        time = currentMonthDate
                        add(Calendar.MONTH, -1)
                    }
                    currentMonthDate = c.time
                }) {
                    Text(text = "◀", color = TealAccent, fontWeight = FontWeight.Bold)
                }

                Text(
                    text = SimpleDateFormat("MMMM yyyy", Locale.ITALIAN).format(currentMonthDate).replaceFirstChar { it.uppercase() },
                    color = Color.White,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold
                )

                IconButton(onClick = {
                    val c = Calendar.getInstance().apply {
                        time = currentMonthDate
                        add(Calendar.MONTH, 1)
                    }
                    currentMonthDate = c.time
                }) {
                    Text(text = "▶", color = TealAccent, fontWeight = FontWeight.Bold)
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Weekday Headers
            Row(modifier = Modifier.fillMaxWidth()) {
                listOf("Lu", "Ma", "Me", "Gi", "Ve", "Sa", "Do").forEach { day ->
                    Text(
                        text = day,
                        color = Color.White.copy(alpha = 0.4f),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.weight(1f)
                    )
                }
            }

            Spacer(modifier = Modifier.height(6.dp))

            // Grid
            val totalCells = leadingEmptySlots + days.size
            val rows = (totalCells + 6) / 7

            Column {
                for (row in 0 until rows) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
                        for (col in 0 until 7) {
                            val cellIndex = row * 7 + col
                            if (cellIndex < leadingEmptySlots || cellIndex >= totalCells) {
                                Box(modifier = Modifier.weight(1f).aspectRatio(1f))
                            } else {
                                val date = days[cellIndex - leadingEmptySlots]
                                CalendarCell(
                                    date = date,
                                    selectedDate = selectedDate,
                                    selectedLocation = selectedLocation,
                                    weatherCache = weatherCache,
                                    onDateSelected = onDateSelected,
                                    modifier = Modifier.weight(1f)
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Legend
            CalendarLegend()
        }
    }
}

@Composable
fun CalendarCell(
    date: Date,
    selectedDate: Date,
    selectedLocation: Location,
    weatherCache: Map<String, FetchedWeatherData>,
    onDateSelected: (Date) -> Unit,
    modifier: Modifier = Modifier
) {
    val cal = Calendar.getInstance().apply { time = date }
    val day = cal.get(Calendar.DAY_OF_MONTH)

    val today = Calendar.getInstance()
    val isToday = Calendar.getInstance().apply { time = date }.let {
        it.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
        it.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR)
    }
    val isSelected = Calendar.getInstance().apply { time = date }.let {
        val sel = Calendar.getInstance().apply { time = selectedDate }
        it.get(Calendar.YEAR) == sel.get(Calendar.YEAR) &&
        it.get(Calendar.DAY_OF_YEAR) == sel.get(Calendar.DAY_OF_YEAR)
    }

    val todayMidnight = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.time
    val cellMidnight = Calendar.getInstance().apply {
        time = date
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.time

    val diffDays = ((cellMidnight.time - todayMidnight.time) / 86400000).toInt()
    val isForecastAvailable = diffDays in -1..7

    // Pull score from cache or calculate
    val activity = activityForDate(date, selectedLocation, weatherCache)

    val baseColor = when (activity) {
        ActivityLevel.BASSA -> ActivityBassa
        ActivityLevel.MODERATA -> ActivityModerata
        ActivityLevel.BUONA -> ActivityBuona
        ActivityLevel.ALTA -> ActivityAlta
        ActivityLevel.MOLTO_ALTA -> ActivityEccezionale
    }

    // Apply forecast parameters decay or saturation
    val cellColor = if (isForecastAvailable) {
        baseColor.copy(alpha = 0.85f)
    } else {
        // Desaturate and make transparent for climatological forecasts
        val alpha = 0.38f
        // Quick greying blend
        Color(
            red = (baseColor.red * 0.45f + 0.55f * 0.4f),
            green = (baseColor.green * 0.45f + 0.55f * 0.4f),
            blue = (baseColor.blue * 0.45f + 0.55f * 0.4f),
            alpha = alpha
        )
    }

    Box(
        modifier = modifier
            .aspectRatio(1f)
            .padding(2.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(cellColor)
            .border(
                width = if (isSelected) 2.dp else if (isToday) 1.dp else 0.dp,
                color = if (isSelected) TealAccent else if (isToday) Color.White else Color.Transparent,
                shape = RoundedCornerShape(8.dp)
            )
            .clickable { onDateSelected(date) },
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = day.toString(),
            color = if (activity == ActivityLevel.BUONA) Color.Black else Color.White,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
fun CalendarLegend() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceAround
    ) {
        listOf(
            Pair("Bassa", ActivityBassa),
            Pair("Mod.", ActivityModerata),
            Pair("Buona", ActivityBuona),
            Pair("Alta", ActivityAlta),
            Pair("Ecc.", ActivityEccezionale)
        ).forEach { pair ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(pair.second.copy(alpha = 0.85f))
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = pair.first,
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 10.sp
                )
            }
        }
    }
}

@Composable
fun DailyActivitySummaryCard(forecast: DailyForecast) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        colors = CardDefaults.cardColors(containerColor = DarkNavy),
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.08f))
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "Attività del Giorno",
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(16.dp))

            val displayLabel = forecast.dailyActivity.description
            val displayColor = when (forecast.dailyActivity) {
                ActivityLevel.BASSA -> ActivityBassa
                ActivityLevel.MODERATA -> ActivityModerata
                ActivityLevel.BUONA -> ActivityBuona
                ActivityLevel.ALTA -> ActivityAlta
                ActivityLevel.MOLTO_ALTA -> ActivityEccezionale
            }

            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .background(displayColor.copy(alpha = 0.15f))
                    .border(1.dp, displayColor.copy(alpha = 0.4f), RoundedCornerShape(12.dp))
                    .padding(horizontal = 24.dp, vertical = 12.dp)
            ) {
                Text(
                    text = displayLabel,
                    color = displayColor,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Black,
                    textAlign = TextAlign.Center
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Ephemerides Grid
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
                AstroItem(label = "☀️ Alba", value = formatTime(forecast.sunrise))
                AstroItem(label = "☀️ Tramonto", value = formatTime(forecast.sunset))
                AstroItem(label = "🌙 Alba Luna", value = formatTime(forecast.moonrise))
                AstroItem(label = "🌙 Tram. Luna", value = formatTime(forecast.moonset))
            }

            Spacer(modifier = Modifier.height(12.dp))

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
                AstroItem(label = "🌓 Fase Lunare", value = forecast.moonPhase)
                AstroItem(label = "🎚️ Coeff. Marea", value = "${forecast.tideCoeffFactor.toInt()}") // Display formatted actual coeff
            }
        }
    }
}

@Composable
fun AstroItem(label: String, value: String) {
    VStack(horizontalAlignment = Alignment.CenterHorizontally, spacing = 2) {
        Text(text = label, color = Color.White.copy(alpha = 0.4f), fontSize = 10.sp, fontWeight = FontWeight.Bold)
        Text(text = value, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun BestWindowsCard(forecast: DailyForecast) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        colors = CardDefaults.cardColors(containerColor = DarkNavy),
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.08f))
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Finestre Migliori di Oggi",
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(12.dp))

            if (forecast.bestWindows.isEmpty()) {
                Text(
                    text = "Nessuna finestra ottimale rilevata per oggi.",
                    color = Color.White.copy(alpha = 0.4f),
                    fontSize = 13.sp,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center
                )
            } else {
                VStack(spacing = 10) {
                    forecast.bestWindows.forEachIndexed { index, window ->
                        val title = when (index) {
                            0 -> "🏆 Miglior Momento"
                            1 -> "🥈 Secondo Momento Utile"
                            else -> "🥉 Finestra Alternativa"
                        }
                        WindowItem(title = title, window = window)
                    }
                }
            }
        }
    }
}

@Composable
fun WindowItem(title: String, window: ActivityWindow) {
    val displayColor = when (window.label) {
        ActivityLevel.BASSA -> ActivityBassa
        ActivityLevel.MODERATA -> ActivityModerata
        ActivityLevel.BUONA -> ActivityBuona
        ActivityLevel.ALTA -> ActivityAlta
        ActivityLevel.MOLTO_ALTA -> ActivityEccezionale
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White.copy(alpha = 0.03f))
            .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(12.dp))
            .padding(12.dp)
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(text = title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .background(displayColor.copy(alpha = 0.15f))
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = window.label.displayName,
                            color = displayColor,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "${window.efficacyPercent}%",
                        color = GoldAccent,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Black
                    )
                }
            }

            Spacer(modifier = Modifier.height(6.dp))

            val timeRange = "${SimpleDateFormat("HH:mm", Locale.ITALIAN).format(window.start)} – ${SimpleDateFormat("HH:mm", Locale.ITALIAN).format(window.end)}"
            Text(text = timeRange, color = TealAccent, fontSize = 13.sp, fontWeight = FontWeight.Bold)

            Spacer(modifier = Modifier.height(6.dp))

            // Drivers
            window.reasons.take(3).forEach { reason ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(text = "•", color = Color.White.copy(alpha = 0.4f), fontSize = 12.sp)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = reason,
                        color = Color.White.copy(alpha = 0.7f),
                        fontSize = 11.sp
                    )
                }
            }
        }
    }
}

@Composable
fun TideChartCard(forecast: DailyForecast, selectedDate: Date) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        colors = CardDefaults.cardColors(containerColor = DarkNavy),
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.08f))
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Andamento Maree",
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Draw custom Canvas Tide Chart
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(130.dp)
            ) {
                TideCanvas(forecast = forecast, selectedDate = selectedDate)
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Tide events text summary
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceAround
            ) {
                forecast.tides.forEach { event ->
                    val typeChar = if (event.type == TideType.ALTA) "▲" else "▼"
                    val typeColor = if (event.type == TideType.ALTA) TealAccent else GrayMuted
                    VStack(horizontalAlignment = Alignment.CenterHorizontally, spacing = 2) {
                        Text(
                            text = "$typeChar ${event.type.displayName}",
                            color = typeColor,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = SimpleDateFormat("HH:mm", Locale.ITALIAN).format(event.time),
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = String.format(Locale.ITALY, "%+.2f m", event.height),
                            color = Color.White.copy(alpha = 0.6f),
                            fontSize = 10.sp
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun TideCanvas(forecast: DailyForecast, selectedDate: Date) {
    val cal = Calendar.getInstance().apply {
        time = selectedDate
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }
    val startOfDay = cal.time

    Canvas(modifier = Modifier.fillMaxSize()) {
        val width = size.width
        val height = size.height
        val centerY = height / 2f

        // Draw mean sea level line
        drawLine(
            color = Color.White.copy(alpha = 0.08f),
            start = Offset(0f, centerY),
            end = Offset(width, centerY),
            strokeWidth = 1f
        )

        // Draw vertical dotted grid lines for hours (0, 6, 12, 18, 24)
        for (h in listOf(6, 12, 18)) {
            val gridX = (h / 24f) * width
            drawLine(
                color = Color.White.copy(alpha = 0.1f),
                start = Offset(gridX, 0f),
                end = Offset(gridX, height),
                strokeWidth = 1f,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f), 0f)
            )
        }

        // Draw Activity Bands (Golden bands for best windows)
        for (window in forecast.bestWindows) {
            val winStartOffset = (window.start.time - startOfDay.time) / 86400000f
            val winEndOffset = (window.end.time - startOfDay.time) / 86400000f

            val bandXStart = winStartOffset * width
            val bandXEnd = winEndOffset * width

            drawRect(
                color = GoldAccent.copy(alpha = 0.04f),
                topLeft = Offset(bandXStart, 0f),
                size = Size(bandXEnd - bandXStart, height)
            )
        }

        // Plot sinusoidal Tide curve
        val path = Path()
        val amplitudeFactor = height * 0.35f
        var maxObservedAmp = 0.15 // fallback
        if (forecast.tides.isNotEmpty()) {
            maxObservedAmp = forecast.tides.map { abs(it.height) }.maxOrNull() ?: 0.15
        }
        val maxAmpVal = max(maxObservedAmp, 0.05)

        for (px in 0..100) {
            val ratio = px / 100f
            val targetTime = Date(startOfDay.time + (ratio * 86400000L).toLong())
            val hVal = TideEngine.calculateHeight(targetTime, forecast.location.coordinate)

            // Convert to canvas Y (positive height points upwards on canvas, which means subtracting)
            val cy = centerY - (hVal / maxAmpVal).toFloat() * amplitudeFactor
            val cx = ratio * width

            if (px == 0) {
                path.moveTo(cx, cy)
            } else {
                path.lineTo(cx, cy)
            }
        }

        drawPath(
            path = path,
            color = TealAccent,
            style = Stroke(width = 2.5f, cap = StrokeCap.Round)
        )

        // Draw Star and TOP labels for tides
        val paintText = Paint().asFrameworkPaint().apply {
            color = android.graphics.Color.WHITE
            textSize = 20f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            textAlign = android.graphics.Paint.Align.CENTER
        }

        val paintTextGold = Paint().asFrameworkPaint().apply {
            color = android.graphics.Color.parseColor("#FFF176")
            textSize = 18f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            textAlign = android.graphics.Paint.Align.CENTER
        }

        for (event in forecast.tides) {
            val offsetRatio = (event.time.time - startOfDay.time) / 86400000f
            val ex = offsetRatio * width
            val ey = centerY - (event.height / maxAmpVal).toFloat() * amplitudeFactor

            // Draw event node point
            drawCircle(
                color = if (event.type == TideType.ALTA) TealAccent else GrayMuted,
                radius = 3.5f,
                center = Offset(ex, ey)
            )

            // Draw peak labels
            val timeText = SimpleDateFormat("HH:mm", Locale.ITALIAN).format(event.time)
            drawContext.canvas.nativeCanvas.drawText(
                timeText,
                ex,
                ey + if (event.type == TideType.ALTA) -8f else 18f,
                paintText
            )

            // Check if this peak matches a best window peak
            val isTopPeak = event.type == TideType.ALTA && forecast.bestWindows.any { window ->
                abs(window.peak.time - event.time.time) <= 7200000 // within 2 hours
            }

            if (isTopPeak) {
                // Draw a small gold star and a tiny bold "TOP" badge
                drawContext.canvas.nativeCanvas.drawText(
                    "★",
                    ex,
                    ey - 22f,
                    paintTextGold
                )
                drawContext.canvas.nativeCanvas.drawText(
                    "TOP",
                    ex,
                    ey - 34f,
                    paintTextGold
                )
            }
        }
    }
}

@Composable
fun CoastalParametersCard(
    cloudCover: Double,
    windDirectionChange: Double,
    swellHeight: Double,
    surfaceTempDelta24h: Double,
    windSpeedMps: Double,
    isFetching: Boolean,
    errorMessage: String?,
    onRefresh: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        colors = CardDefaults.cardColors(containerColor = DarkNavy),
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.08f))
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Meteo & Parametri Costieri",
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )

                if (isFetching) {
                    CircularProgressIndicator(
                        color = TealAccent,
                        modifier = Modifier.size(14.dp),
                        strokeWidth = 2.dp
                    )
                } else {
                    Text(
                        text = "Aggiorna ↻",
                        color = TealAccent,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.clickable { onRefresh() }
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            VStack(spacing = 12) {
                ParameterItem(
                    icon = "☁️",
                    label = "Nuvolosità",
                    value = "${cloudCover.toInt()}%",
                    color = Color.Cyan
                )
                Divider(color = Color.White.copy(alpha = 0.05f))
                ParameterItem(
                    icon = "💨",
                    label = "Variazione Direzione Vento",
                    value = "${windDirectionChange.toInt()}°",
                    color = Color(0xFFFFB74D)
                )
                Divider(color = Color.White.copy(alpha = 0.05f))
                ParameterItem(
                    icon = "🌀",
                    label = "Velocità Vento Sostenuto",
                    value = String.format(Locale.ITALY, "%.1f m/s", windSpeedMps),
                    color = Color(0xFFFFF176)
                )
                Divider(color = Color.White.copy(alpha = 0.05f))
                ParameterItem(
                    icon = "🌊",
                    label = "Altezza Onda (Swell)",
                    value = String.format(Locale.ITALY, "%.1f m", swellHeight),
                    color = Color(0xFF64B5F6)
                )
                Divider(color = Color.White.copy(alpha = 0.05f))
                ParameterItem(
                    icon = "🌡️",
                    label = "Variazione Temp. Superficiale (24h)",
                    value = String.format(Locale.ITALY, "%+.1f°C", surfaceTempDelta24h),
                    color = if (surfaceTempDelta24h < -1.5) ActivityEccezionale else Color.White
                )
            }

            errorMessage?.let { msg ->
                Spacer(modifier = Modifier.height(10.dp))
                Text(
                    text = msg,
                    color = ActivityBassa,
                    fontSize = 11.sp,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center
                )
            }

            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "* Rilevamenti costieri e satellitari aggiornati via Open-Meteo.",
                fontSize = 9.sp,
                color = Color.White.copy(alpha = 0.3f),
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
fun ParameterItem(
    icon: String,
    label: String,
    value: String,
    color: Color
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text = icon, fontSize = 14.sp)
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = label,
                color = Color.White.copy(alpha = 0.8f),
                fontSize = 13.sp
            )
        }
        Text(
            text = value,
            color = color,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

// Helpers
private fun formatTime(date: Date?): String {
    if (date == null) return "--:--"
    return SimpleDateFormat("HH:mm", Locale.ITALIAN).format(date)
}

// Layout helper widgets
@Composable
fun VStack(
    modifier: Modifier = Modifier,
    horizontalAlignment: Alignment.Horizontal = Alignment.Start,
    spacing: Int = 0,
    content: @Composable () -> Unit
) {
    Column(
        modifier = modifier,
        horizontalAlignment = horizontalAlignment,
        verticalArrangement = Arrangement.spacedBy(spacing.dp)
    ) {
        content()
    }
}
