//
//  WeatherTool.swift
//  Beth
//
//  THE INTERNET, SOLVED.
//
//  The on-device model has no clock, no network, and almost no world
//  knowledge. That is not a limitation you work around. It is the
//  design. The model's job is to understand the request and decide
//  what is needed. Your code's job is to go get it.
//
//  The Foundation Models framework implements tool calling for exactly
//  this. You define a struct conforming to Tool, hand it to the
//  session, and when the model decides it needs live data it calls
//  YOUR function with structured arguments. Your function hits the
//  network, returns a string, and the model writes the answer around it.
//
//  So the flow for "what is the weather in Albuquerque" is:
//
//    1. Model reads the request, recognizes it needs weather
//    2. Model calls getWeather(city: "Albuquerque")   <- your Swift code
//    3. Your code hits a public API over HTTPS
//    4. Your code returns the numbers
//    5. Model writes a sentence around them
//
//  Steps 3 and 4 are ordinary networking. Deterministic, free, correct.
//  The model never has to know anything.
//
//  This is how Siri and Alexa have always worked underneath. Intent
//  classification plus tool execution. The language model is the front
//  door, not the house.
//
//  API NOTE: Open-Meteo is used here because it needs no API key and
//  no account. Geocoding and forecast are two separate free endpoints.
//
//  SETUP REQUIRED: in Xcode, select the target, Signing and
//  Capabilities, and under App Sandbox check "Outgoing Connections
//  (Client)". Without it every request fails silently with a sandbox
//  error, which looks exactly like a broken tool.
//

import Foundation
import FoundationModels

struct WeatherTool: Tool {

    // What the model sees when deciding whether to call this.
    // Treat the description as prompt engineering: it is the only
    // thing telling the model when this tool applies.
    let name = "getWeather"
    let description = """
    Get the current weather and temperature for a named city or place. \
    Use this whenever the user asks about weather, temperature, or \
    whether they need a jacket or umbrella.
    """

    // The model fills this in. Same @Generable machinery as AppAction,
    // so the arguments are guaranteed to match the shape.
    @Generable
    struct Arguments {
        @Guide(description: "The city or place name, for example 'Albuquerque' or 'Santa Fe, New Mexico'.")
        var city: String
    }

    // The model calls this. Everything below is ordinary Swift.
    func call(arguments: Arguments) async throws -> String {
        let place = try await Self.geocode(arguments.city)
        let weather = try await Self.currentWeather(
            latitude: place.latitude,
            longitude: place.longitude
        )

        // Return plain text. The model reads this and writes prose
        // around it. Keep it factual and compact; anything you put
        // here is something the model may repeat.
        return """
        Location: \(place.name)\(place.admin1.map { ", \($0)" } ?? "")
        Temperature: \(Int(weather.temperature.rounded())) degrees Fahrenheit
        Feels like: \(Int(weather.apparent.rounded())) degrees
        Conditions: \(Self.describe(code: weather.weatherCode))
        Wind: \(Int(weather.windSpeed.rounded())) mph
        """
    }

    // MARK: - Networking

    private struct Place {
        let name: String
        let admin1: String?
        let latitude: Double
        let longitude: Double
    }

    private struct Weather {
        let temperature: Double
        let apparent: Double
        let windSpeed: Double
        let weatherCode: Int
    }

    /// Turns a place name into coordinates.
    private static func geocode(_ query: String) async throws -> Place {
        var components = URLComponents(
            string: "https://geocoding-api.open-meteo.com/v1/search"
        )!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)

        guard let first = decoded.results?.first else {
            throw ToolError.placeNotFound(query)
        }
        return Place(
            name: first.name,
            admin1: first.admin1,
            latitude: first.latitude,
            longitude: first.longitude
        )
    }

    /// Fetches current conditions for a coordinate.
    private static func currentWeather(
        latitude: Double,
        longitude: Double
    ) async throws -> Weather {
        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/forecast"
        )!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current",
                         value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)

        return Weather(
            temperature: decoded.current.temperature_2m,
            apparent: decoded.current.apparent_temperature,
            windSpeed: decoded.current.wind_speed_10m,
            weatherCode: decoded.current.weather_code
        )
    }

    // MARK: - JSON shapes

    private struct GeocodeResponse: Decodable {
        let results: [Result]?
        struct Result: Decodable {
            let name: String
            let admin1: String?
            let latitude: Double
            let longitude: Double
        }
    }

    private struct ForecastResponse: Decodable {
        let current: Current
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let wind_speed_10m: Double
        }
    }

    /// WMO weather codes to plain English.
    private static func describe(code: Int) -> String {
        switch code {
        case 0: return "clear sky"
        case 1: return "mainly clear"
        case 2: return "partly cloudy"
        case 3: return "overcast"
        case 45, 48: return "foggy"
        case 51, 53, 55: return "drizzle"
        case 56, 57: return "freezing drizzle"
        case 61, 63, 65: return "rain"
        case 66, 67: return "freezing rain"
        case 71, 73, 75: return "snow"
        case 77: return "snow grains"
        case 80, 81, 82: return "rain showers"
        case 85, 86: return "snow showers"
        case 95: return "thunderstorm"
        case 96, 99: return "thunderstorm with hail"
        default: return "unknown conditions"
        }
    }

    enum ToolError: LocalizedError {
        case placeNotFound(String)

        var errorDescription: String? {
            switch self {
            case .placeNotFound(let query):
                return "Could not find a place named \(query)."
            }
        }
    }
}

//
//  A SECOND TOOL, because the model also has no clock.
//
//  Yesterday it could not tell you what day it is. Eight lines of code
//  and now it can. Worth sitting with: that was never a model problem.
//
struct DateTimeTool: Tool {

    let name = "getCurrentDateTime"
    let description = """
    Get the current date and time. Use this whenever the user asks what \
    day, date, or time it is, or asks about anything relative to now \
    such as tomorrow, next week, or how many days until something.
    """

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return "Current date and time: \(formatter.string(from: Date()))"
    }
}
