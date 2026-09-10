import Foundation

public enum ModelPricingCatalog {
    public static let fallback = ModelPricing(
        pattern: "fallback-sonnet",
        displayName: "Fallback Sonnet",
        family: "fallback",
        inputPerMTok: 3.00,
        outputPerMTok: 15.00,
        cacheReadPerMTok: 0.30,
        cacheCreationPerMTok: 3.75,
        reasoningPerMTok: 15.00
    )

    public static let defaults: [ModelPricing] = [
        ModelPricing(pattern: "claude-opus-4-5", family: "anthropic", inputPerMTok: 5.00, outputPerMTok: 25.00, cacheReadPerMTok: 0.50, cacheCreationPerMTok: 6.25, reasoningPerMTok: 25.00),
        ModelPricing(pattern: "claude-opus-4-6", family: "anthropic", inputPerMTok: 5.00, outputPerMTok: 25.00, cacheReadPerMTok: 0.50, cacheCreationPerMTok: 6.25, reasoningPerMTok: 25.00),
        ModelPricing(pattern: "claude-opus-4-7", family: "anthropic", inputPerMTok: 5.00, outputPerMTok: 25.00, cacheReadPerMTok: 0.50, cacheCreationPerMTok: 6.25, reasoningPerMTok: 25.00),
        ModelPricing(pattern: "claude-opus-4-8", family: "anthropic", inputPerMTok: 5.00, outputPerMTok: 25.00, cacheReadPerMTok: 0.50, cacheCreationPerMTok: 6.25, reasoningPerMTok: 25.00),
        ModelPricing(pattern: "claude-sonnet-4-5", family: "anthropic", inputPerMTok: 3.00, outputPerMTok: 15.00, cacheReadPerMTok: 0.30, cacheCreationPerMTok: 3.75, reasoningPerMTok: 15.00),
        ModelPricing(pattern: "claude-sonnet-4-6", family: "anthropic", inputPerMTok: 3.00, outputPerMTok: 15.00, cacheReadPerMTok: 0.30, cacheCreationPerMTok: 3.75, reasoningPerMTok: 15.00),
        ModelPricing(pattern: "claude-haiku-4-5", family: "anthropic", inputPerMTok: 1.00, outputPerMTok: 5.00, cacheReadPerMTok: 0.10, cacheCreationPerMTok: 1.25, reasoningPerMTok: 5.00),
        ModelPricing(pattern: "claude-3-5-sonnet", family: "anthropic", inputPerMTok: 3.00, outputPerMTok: 15.00, cacheReadPerMTok: 0.30, cacheCreationPerMTok: 3.75, reasoningPerMTok: 15.00),
        ModelPricing(pattern: "claude-3-5-haiku", family: "anthropic", inputPerMTok: 0.80, outputPerMTok: 4.00, cacheReadPerMTok: 0.08, cacheCreationPerMTok: 1.00, reasoningPerMTok: 4.00),
        ModelPricing(pattern: "claude-3-opus", family: "anthropic", inputPerMTok: 15.00, outputPerMTok: 75.00, cacheReadPerMTok: 1.50, cacheCreationPerMTok: 18.75, reasoningPerMTok: 75.00),

        ModelPricing(pattern: "gpt-5.5", family: "openai", inputPerMTok: 5.00, outputPerMTok: 30.00, cacheReadPerMTok: 0.50, reasoningPerMTok: 30.00),
        ModelPricing(pattern: "gpt-5.4", family: "openai", inputPerMTok: 2.50, outputPerMTok: 15.00, cacheReadPerMTok: 0.25, reasoningPerMTok: 15.00),
        ModelPricing(pattern: "gpt-5.3", family: "openai", inputPerMTok: 1.75, outputPerMTok: 14.00, cacheReadPerMTok: 0.175, reasoningPerMTok: 14.00),
        ModelPricing(pattern: "gpt-5.2", family: "openai", inputPerMTok: 1.75, outputPerMTok: 14.00, cacheReadPerMTok: 0.175, reasoningPerMTok: 14.00),
        ModelPricing(pattern: "gpt-5.1", family: "openai", inputPerMTok: 1.25, outputPerMTok: 10.00, cacheReadPerMTok: 0.125, reasoningPerMTok: 10.00),
        ModelPricing(pattern: "gpt-5-codex", family: "openai", inputPerMTok: 1.25, outputPerMTok: 10.00, cacheReadPerMTok: 0.125, reasoningPerMTok: 10.00),
        ModelPricing(pattern: "gpt-5-mini", family: "openai", inputPerMTok: 0.25, outputPerMTok: 2.00, cacheReadPerMTok: 0.025, reasoningPerMTok: 2.00),
        ModelPricing(pattern: "gpt-5-nano", family: "openai", inputPerMTok: 0.05, outputPerMTok: 0.40, cacheReadPerMTok: 0.005, reasoningPerMTok: 0.40),
        ModelPricing(pattern: "gpt-5", family: "openai", inputPerMTok: 1.25, outputPerMTok: 10.00, cacheReadPerMTok: 0.125, reasoningPerMTok: 10.00),

        ModelPricing(pattern: "gpt-4o", family: "openai", inputPerMTok: 2.50, outputPerMTok: 10.00, reasoningPerMTok: 10.00),
        ModelPricing(pattern: "gpt-4o-mini", family: "openai", inputPerMTok: 0.15, outputPerMTok: 0.60, reasoningPerMTok: 0.60),
        ModelPricing(pattern: "gpt-4.1", family: "openai", inputPerMTok: 2.00, outputPerMTok: 8.00, reasoningPerMTok: 8.00),

        ModelPricing(pattern: "o1", family: "openai", inputPerMTok: 15.00, outputPerMTok: 60.00, reasoningPerMTok: 60.00),
        ModelPricing(pattern: "o1-mini", family: "openai", inputPerMTok: 1.10, outputPerMTok: 4.40, reasoningPerMTok: 4.40),
        ModelPricing(pattern: "o3", family: "openai", inputPerMTok: 2.00, outputPerMTok: 8.00, reasoningPerMTok: 8.00),
        ModelPricing(pattern: "o3-mini", family: "openai", inputPerMTok: 1.10, outputPerMTok: 4.40, reasoningPerMTok: 4.40),
        ModelPricing(pattern: "o4-mini", family: "openai", inputPerMTok: 1.10, outputPerMTok: 4.40, reasoningPerMTok: 4.40),

        ModelPricing(pattern: "gemini-3-pro", family: "google", inputPerMTok: 2.00, outputPerMTok: 12.00, cacheReadPerMTok: 0.20, reasoningPerMTok: 12.00),
        ModelPricing(pattern: "gemini-3-flash", family: "google", inputPerMTok: 0.50, outputPerMTok: 3.00, cacheReadPerMTok: 0.05, reasoningPerMTok: 3.00),
        ModelPricing(pattern: "gemini-2.5-pro", family: "google", inputPerMTok: 1.25, outputPerMTok: 10.00, cacheReadPerMTok: 0.625, reasoningPerMTok: 10.00),
        ModelPricing(pattern: "gemini-2.5-flash", family: "google", inputPerMTok: 0.15, outputPerMTok: 0.60, cacheReadPerMTok: 0.075, reasoningPerMTok: 0.60),

        ModelPricing(pattern: "grok-4.5", family: "xai", inputPerMTok: 2.00, outputPerMTok: 6.00, cacheReadPerMTok: 0.30, cacheCreationPerMTok: 2.00, reasoningPerMTok: 6.00),
        ModelPricing(pattern: "grok-build-0.1", family: "xai", inputPerMTok: 1.00, outputPerMTok: 2.00, cacheReadPerMTok: 0.20, cacheCreationPerMTok: 1.00, reasoningPerMTok: 2.00),
        ModelPricing(pattern: "grok-build-latest", family: "xai", inputPerMTok: 2.00, outputPerMTok: 6.00, cacheReadPerMTok: 0.30, cacheCreationPerMTok: 2.00, reasoningPerMTok: 6.00),
        ModelPricing(pattern: "grok-4.3", family: "xai", inputPerMTok: 1.25, outputPerMTok: 2.50, cacheReadPerMTok: 0.20, cacheCreationPerMTok: 1.25, reasoningPerMTok: 2.50),
        ModelPricing(pattern: "grok-4.20", family: "xai", inputPerMTok: 1.25, outputPerMTok: 2.50, cacheReadPerMTok: 0.20, cacheCreationPerMTok: 1.25, reasoningPerMTok: 2.50),
        ModelPricing(pattern: "grok-code-fast-1", family: "xai", inputPerMTok: 1.25, outputPerMTok: 2.50, cacheReadPerMTok: 0.20, cacheCreationPerMTok: 1.25, reasoningPerMTok: 2.50),
        ModelPricing(pattern: "grok-3", family: "xai", inputPerMTok: 1.25, outputPerMTok: 2.50, cacheReadPerMTok: 0.20, cacheCreationPerMTok: 1.25, reasoningPerMTok: 2.50),
        ModelPricing(pattern: "deepseek-v3", family: "deepseek", inputPerMTok: 0.27, outputPerMTok: 1.10, reasoningPerMTok: 1.10),
        ModelPricing(pattern: "deepseek-r1", family: "deepseek", inputPerMTok: 0.55, outputPerMTok: 2.19, reasoningPerMTok: 2.19)
    ]

    public static func match(model: String, in pricing: [ModelPricing]) -> ModelPricing {
        let lower = model.lowercased()
        var best: ModelPricing?
        var bestLength = 0

        for row in pricing {
            let pattern = row.pattern.lowercased()
            if lower.contains(pattern), pattern.count > bestLength {
                best = row
                bestLength = pattern.count
            }
        }

        return best ?? fallback
    }

    public static func estimateCostUSD(tokens: TokenEntry, pricing: ModelPricing) -> Double {
        Double(tokens.inputTokens) / 1_000_000 * pricing.inputPerMTok
            + Double(tokens.outputTokens) / 1_000_000 * pricing.outputPerMTok
            + Double(tokens.cachedInputTokens) / 1_000_000 * pricing.cacheReadPerMTok
            + Double(tokens.cacheCreationInputTokens) / 1_000_000 * pricing.cacheCreationPerMTok
            + Double(tokens.reasoningOutputTokens) / 1_000_000 * pricing.reasoningPerMTok
    }
}
