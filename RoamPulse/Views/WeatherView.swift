import SwiftUI

/// Weather and activity advisories for one trip, from OpenWeatherMap (or sample data without an API key).
struct WeatherView: View {
    @State private var viewModel: WeatherViewModel

    init(viewModel: WeatherViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let weather = viewModel.snapshot {
                    content(weather)
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("No forecast", systemImage: "cloud.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await viewModel.load(refresh: true) } }
                    }
                } else {
                    ProgressView("Loading forecast…")
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Weather")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.load(refresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                        .animation(viewModel.isLoading ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                                   value: viewModel.isLoading)
                }
                .accessibilityLabel("Refresh forecast")
            }
        }
        .refreshable { await viewModel.load(refresh: true) }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func content(_ weather: WeatherSnapshot) -> some View {
        if let offline = viewModel.offlineText {
            Label(offline, systemImage: "wifi.slash")
                .font(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        currentCard(weather)

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            metric("Humidity", "\(weather.humidity)%")
            metric("Wind", "\(weather.windKmh) km/h")
            metric("Rain Probability", "\(weather.rainChance)%")
            metric("Sunset", weather.sunset)
        }

        if let advisory = viewModel.advisory {
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
                    .accessibilityElement(children: .combine)
                }
            }
        }

        if viewModel.activityAdvisories.count > 1 {
            SectionLabel("Plans at risk").padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(viewModel.activityAdvisories, id: \.advisory.activityID) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.advisory.icon).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Day \(item.activity.day) • \(item.activity.timeText) \(item.activity.title)").font(.headline)
                            Text(item.advisory.message).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .accessibilityElement(children: .combine)
                    if item.advisory.activityID != viewModel.activityAdvisories.last?.advisory.activityID { Divider() }
                }
            }
            .card(padding: 0)
        }

        SectionLabel("5-Day Forecast").padding(.top, 6)
        VStack(spacing: 0) {
            ForEach(weather.daily) { day in
                dailyRow(day)
                if day.id != weather.daily.last?.id { Divider() }
            }
        }
        .card(padding: 0)

        Text(viewModel.updatedText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
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
                NavigationLink("View Day \(advisory.day) Schedule", value: AppRoute.tripDetail(viewModel.tripID, day: advisory.day))
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
    let dependencies = AppDependencies.preview()
    NavigationStack {
        WeatherView(viewModel: WeatherViewModel(tripID: dependencies.previewTripID, store: dependencies.store,
                                                weather: dependencies.weather))
    }
    .previewEnvironment(dependencies)
}
