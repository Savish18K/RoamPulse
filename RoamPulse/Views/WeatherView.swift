import SwiftUI

/// Weather and activity advisories. Uses the saved mock forecast for now;
/// OpenWeatherMap will be called from here later.
struct WeatherView: View {
    let tripID: UUID
    @Environment(TripStore.self) private var store
    @State private var isRefreshing = false
    @State private var updatedAt: String?

    var body: some View {
        let weather = store.weather

        ScrollView {
            VStack(spacing: 14) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                                   value: isRefreshing)
                }
                .accessibilityLabel("Refresh forecast")

                currentCard(weather)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    metric("Humidity", "\(weather.humidity)%")
                    metric("Wind", "\(weather.windKmh) km/h")
                    metric("Rain Probability", "\(weather.rainChance)%")
                    metric("Sunset", weather.sunset)
                }

                if let advisory = weather.advisory {
                    advisoryCard(advisory)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(weather.hourly) { hour in
                            VStack(spacing: 8) {
                                Text(hour.label).font(.caption).foregroundStyle(.secondary)
                                Image(systemName: hour.symbol)
                                    .symbolRenderingMode(.multicolor)
                                    .foregroundStyle(.cyan)
                                Text("\(hour.temperature)°").font(.headline)
                                Text("\(hour.rainChance)%").font(.caption).foregroundStyle(.cyan)
                            }
                            .frame(width: 68)
                            .padding(.vertical, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
                        }
                    }
                }

                SectionLabel("5-Day Forecast").padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(weather.daily) { day in
                        dailyRow(day)
                        if day.id != weather.daily.last?.id { Divider() }
                    }
                }
                .card(padding: 0)

                Text("Updated \(updatedAt ?? weather.updatedAt) • OpenWeatherMap data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Weather")
        .refreshable { await refresh() }
    }

    private func refresh() async {
        isRefreshing = true
        try? await Task.sleep(for: .seconds(1))
        updatedAt = DemoClock.minutesNow.clockText
        isRefreshing = false
    }

    private func currentCard(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(weather.location).font(.largeTitle.bold())
                    Text(weather.condition).font(.title3)
                }
                Spacer()
                Text("\(weather.temperature)°").font(.system(size: 76, weight: .bold))
            }
            HStack {
                Text("H\(weather.high) L\(weather.low)")
                Spacer()
                Text("Active Location")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.2), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(
            LinearGradient(colors: [Color(hex: 0x5AC8FA), Color(hex: 0x0A6CF0)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .card(padding: 14, cornerRadius: 16)
    }

    private func advisoryCard(_ advisory: WeatherAdvisory) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(advisory.title).font(.headline).foregroundStyle(.orange)
                Text(advisory.message).font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("View Day \(advisory.day) Schedule", value: AppRoute.tripDetail(tripID, day: advisory.day))
                    .font(.subheadline.bold())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.orange.opacity(0.7)))
    }

    private func dailyRow(_ day: DailyForecast) -> some View {
        HStack(spacing: 10) {
            Text(day.dayLabel).font(.headline).frame(width: 64, alignment: .leading)
            if let tripDay = day.tripDay {
                Text("Day \(tripDay)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 6))
            }
            Spacer()
            Label(day.condition, systemImage: day.symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let rain = day.rainChance {
                Text("\(rain)%").font(.caption.bold()).foregroundStyle(.cyan)
            }
            Spacer()
            Text("\(day.high)/\(day.low)").font(.headline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    NavigationStack { WeatherView(tripID: SampleData.hillCountry.id) }
        .environment(TripStore())
        .preferredColorScheme(.dark)
}
