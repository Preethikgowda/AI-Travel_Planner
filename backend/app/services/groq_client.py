import json
from decimal import Decimal
from typing import Any

import httpx

from app.core.config import settings
from app.schemas.ai import (
    BudgetOptimizerRequest,
    ChatRequest,
    DestinationCompareRequest,
    ItineraryRequest,
    PackingListRequest,
)


class TravelAIService:
    async def generate_itinerary(self, payload: ItineraryRequest) -> dict[str, Any]:
        fallback = self._fallback_itinerary(payload)
        prompt = (
            "Create a practical travel itinerary as strict JSON with keys "
            "trip_summary, day_wise_plan, estimated_budget_breakdown, travel_tips. "
            "day_wise_plan must be an array of objects with day, title, morning, afternoon, evening. "
            f"Destination: {payload.destination}. Budget: {payload.budget}. Days: {payload.days}. "
            f"Interests: {', '.join(payload.interests) or 'general sightseeing'}."
        )
        generated = await self._complete_json(prompt, fallback)
        return self._normalize_itinerary(generated, fallback)

    async def chat(self, payload: ChatRequest) -> dict[str, Any]:
        fallback = {
            "answer": (
                "A balanced travel plan should confirm dates, local transit, weather, reservations, "
                "daily pacing, and a buffer for delays. For your question: "
                f"{payload.question}"
            )
        }
        prompt = (
            "You are a concise AI travel assistant. Return strict JSON with exactly one key: answer. "
            "The answer value must be one helpful plain-text string, not an object or array. "
            f"Answer this traveler question with actionable advice: {payload.question}"
        )
        generated = await self._complete_json(prompt, fallback)
        return self._normalize_chat(generated, fallback)

    async def optimize_budget(self, payload: BudgetOptimizerRequest) -> dict[str, Any]:
        daily = self._money(payload.budget / payload.days)
        fallback = {
            "budget_saving_suggestions": [
                f"Target an average daily spend near {daily} in {payload.destination}.",
                "Book refundable lodging early, then recheck prices two weeks before travel.",
                "Use public transit or day passes for routine transfers.",
                "Choose one paid anchor activity per day and fill the rest with free neighborhoods, markets, and viewpoints.",
                "Track meals separately so dining does not absorb the activity budget.",
            ]
        }
        prompt = (
            "Return strict JSON with key budget_saving_suggestions as an array of strings. "
            f"Optimize a {payload.days}-day trip to {payload.destination} with total budget {payload.budget}."
        )
        generated = await self._complete_json(prompt, fallback)
        suggestions = generated.get("budget_saving_suggestions")
        if isinstance(suggestions, dict):
            suggestions = [f"{key.replace('_', ' ').title()}: {value}" for key, value in suggestions.items()]
        if not isinstance(suggestions, list):
            return fallback
        return {"budget_saving_suggestions": [str(item) for item in suggestions]}

    async def compare_destinations(self, payload: DestinationCompareRequest) -> dict[str, Any]:
        fallback = {
            "cost_comparison": {
                payload.destination_a: "Often best for travelers who prioritize local dining, transit, and compact daily routes.",
                payload.destination_b: "Often best when flight pricing or hotel availability is stronger for your dates.",
            },
            "weather_comparison": {
                payload.destination_a: "Check month-specific forecasts before booking outdoor-heavy days.",
                payload.destination_b: "Compare seasonal rain, heat, and daylight against your planned activities.",
            },
            "activity_comparison": {
                payload.destination_a: "Strong choice for culture, food, walking routes, and neighborhood exploration.",
                payload.destination_b: "Strong choice for varied attractions, shopping, nightlife, and day trips.",
            },
            "best_choice": (
                f"Choose {payload.destination_a} for a slower culture-focused trip; choose "
                f"{payload.destination_b} if logistics and prices are better for your dates."
            ),
        }
        prompt = (
            "Compare two destinations for a traveler. Return strict JSON with keys cost_comparison, "
            "weather_comparison, activity_comparison, best_choice. Each comparison must be an object. "
            f"Destination A: {payload.destination_a}. Destination B: {payload.destination_b}."
        )
        generated = await self._complete_json(prompt, fallback)
        return self._normalize_comparison(generated, fallback)

    async def packing_list(self, payload: PackingListRequest) -> dict[str, Any]:
        fallback = {
            "packing_list": [
                {"category": "Documents", "items": ["Passport or government ID", "Travel insurance", "Booking confirmations", "Emergency contacts"]},
                {"category": "Clothing", "items": ["Comfortable walking shoes", "Layered outfits", "Weather-appropriate outerwear", "Sleepwear"]},
                {"category": "Health", "items": ["Prescription medication", "Basic first-aid kit", "Sunscreen", "Reusable water bottle"]},
                {"category": "Electronics", "items": ["Phone charger", "Power bank", "Universal adapter", "Offline maps"]},
                {"category": "Destination Specific", "items": [f"Month-aware outfit plan for {payload.travel_month}", f"Small day bag for {payload.destination}"]},
            ]
        }
        prompt = (
            "Return strict JSON with key packing_list. packing_list must be an array of objects with "
            "category and items array. "
            f"Destination: {payload.destination}. Travel month: {payload.travel_month}."
        )
        generated = await self._complete_json(prompt, fallback)
        return self._normalize_packing_list(generated, fallback)

    async def _complete_json(self, prompt: str, fallback: dict[str, Any]) -> dict[str, Any]:
        if not settings.groq_api_key:
            return fallback

        headers = {
            "Authorization": f"Bearer {settings.groq_api_key}",
            "Content-Type": "application/json",
        }
        body = {
            "model": settings.groq_model,
            "temperature": 0.35,
            "response_format": {"type": "json_object"},
            "messages": [
                {
                    "role": "system",
                    "content": "You are a production travel-planning API. Return valid JSON only, with no markdown.",
                },
                {"role": "user", "content": prompt},
            ],
        }
        try:
            async with httpx.AsyncClient(timeout=settings.groq_timeout_seconds) as client:
                response = await client.post(settings.groq_base_url, headers=headers, json=body)
                response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            return self._parse_json(content)
        except (httpx.HTTPError, KeyError, IndexError, TypeError, json.JSONDecodeError, ValueError):
            return fallback

    @staticmethod
    def _parse_json(content: str) -> dict[str, Any]:
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            start = content.find("{")
            end = content.rfind("}") + 1
            if start < 0 or end <= start:
                raise
            return json.loads(content[start:end])

    def _fallback_itinerary(self, payload: ItineraryRequest) -> dict[str, Any]:
        interests = payload.interests or ["local food", "landmarks", "neighborhood walks"]
        per_day = payload.budget / payload.days if payload.days else Decimal("0")
        day_wise_plan = []
        for day in range(1, payload.days + 1):
            focus = interests[(day - 1) % len(interests)]
            day_wise_plan.append(
                {
                    "day": day,
                    "title": f"{payload.destination} day {day}: {focus.title()}",
                    "morning": f"Start with a low-crowd visit around a key {focus} area and use public transit where practical.",
                    "afternoon": f"Plan a reserved activity or guided experience tied to {focus}, with a flexible lunch nearby.",
                    "evening": "Keep dinner close to the next morning's route and leave a buffer for rest or a short walk.",
                }
            )

        return {
            "trip_summary": (
                f"{payload.days} days in {payload.destination} with a total budget of {self._money(payload.budget)}. "
                "The plan balances anchor activities, flexible exploration, and daily recovery time."
            ),
            "day_wise_plan": day_wise_plan,
            "estimated_budget_breakdown": {
                "lodging": self._money(payload.budget * Decimal("0.40")),
                "food": self._money(payload.budget * Decimal("0.25")),
                "activities": self._money(payload.budget * Decimal("0.20")),
                "transport": self._money(payload.budget * Decimal("0.15")),
                "daily_target": self._money(per_day),
            },
            "travel_tips": [
                "Book timed-entry attractions before arrival.",
                "Group nearby activities to reduce transit time.",
                "Keep one flexible block every two days for weather or fatigue.",
                "Download offline maps and save hotel details locally.",
            ],
        }

    @staticmethod
    def _normalize_itinerary(generated: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
        summary = generated.get("trip_summary", fallback["trip_summary"])
        if isinstance(summary, dict):
            summary = ", ".join(f"{key.replace('_', ' ')}: {value}" for key, value in summary.items())
        if not isinstance(summary, str):
            summary = fallback["trip_summary"]

        raw_days = generated.get("day_wise_plan", fallback["day_wise_plan"])
        day_wise_plan = []
        if isinstance(raw_days, dict):
            raw_days = list(raw_days.values())
        if isinstance(raw_days, list):
            for index, item in enumerate(raw_days, start=1):
                if isinstance(item, str):
                    day_wise_plan.append(
                        {
                            "day": index,
                            "title": f"Day {index}",
                            "morning": item,
                            "afternoon": "Explore nearby areas at a comfortable pace.",
                            "evening": "Keep the evening flexible for dinner and rest.",
                        }
                    )
                    continue
                if not isinstance(item, dict):
                    continue
                day_number = item.get("day", index)
                if isinstance(day_number, str):
                    digits = "".join(character for character in day_number if character.isdigit())
                    day_number = int(digits) if digits else index
                activities = item.get("activities")
                if isinstance(activities, list):
                    activity_text = "; ".join(str(activity) for activity in activities)
                else:
                    activity_text = str(activities or "")
                day_wise_plan.append(
                    {
                        "day": int(day_number),
                        "title": str(item.get("title") or item.get("theme") or f"Day {index}"),
                        "morning": str(item.get("morning") or item.get("morning_activity") or activity_text or fallback["day_wise_plan"][0]["morning"]),
                        "afternoon": str(item.get("afternoon") or item.get("afternoon_activity") or activity_text or fallback["day_wise_plan"][0]["afternoon"]),
                        "evening": str(item.get("evening") or item.get("evening_activity") or item.get("night") or fallback["day_wise_plan"][0]["evening"]),
                    }
                )
        if not day_wise_plan:
            day_wise_plan = fallback["day_wise_plan"]

        raw_budget = generated.get("estimated_budget_breakdown", fallback["estimated_budget_breakdown"])
        if isinstance(raw_budget, dict):
            budget = {str(key): str(value) for key, value in raw_budget.items()}
        else:
            budget = fallback["estimated_budget_breakdown"]

        raw_tips = generated.get("travel_tips", fallback["travel_tips"])
        if isinstance(raw_tips, dict):
            tips = [f"{key.replace('_', ' ').title()}: {value}" for key, value in raw_tips.items()]
        elif isinstance(raw_tips, list):
            tips = [str(tip) for tip in raw_tips]
        elif isinstance(raw_tips, str):
            tips = [raw_tips]
        else:
            tips = fallback["travel_tips"]

        return {
            "trip_summary": summary,
            "day_wise_plan": day_wise_plan,
            "estimated_budget_breakdown": budget,
            "travel_tips": tips,
        }

    @staticmethod
    def _normalize_comparison(generated: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
        def as_string_map(value: Any, fallback_value: dict[str, str]) -> dict[str, str]:
            if isinstance(value, dict):
                return {str(key): str(item) for key, item in value.items()}
            if isinstance(value, str):
                return {"summary": value}
            return fallback_value

        return {
            "cost_comparison": as_string_map(generated.get("cost_comparison"), fallback["cost_comparison"]),
            "weather_comparison": as_string_map(generated.get("weather_comparison"), fallback["weather_comparison"]),
            "activity_comparison": as_string_map(generated.get("activity_comparison"), fallback["activity_comparison"]),
            "best_choice": str(generated.get("best_choice") or fallback["best_choice"]),
        }

    @staticmethod
    def _normalize_chat(generated: dict[str, Any], fallback: dict[str, Any]) -> dict[str, str]:
        answer = generated.get("answer")
        if answer is None:
            answer = generated

        if isinstance(answer, str):
            cleaned = answer.strip()
        else:
            cleaned = TravelAIService._stringify_ai_value(answer).strip()

        return {"answer": cleaned or fallback["answer"]}

    @staticmethod
    def _stringify_ai_value(value: Any) -> str:
        if isinstance(value, dict):
            lines = []
            for key, item in value.items():
                label = str(key).replace("_", " ").title()
                if isinstance(item, list):
                    rendered = "; ".join(TravelAIService._stringify_ai_value(entry) for entry in item)
                elif isinstance(item, dict):
                    rendered = ", ".join(
                        f"{str(child_key).replace('_', ' ').title()}: {TravelAIService._stringify_ai_value(child_value)}"
                        for child_key, child_value in item.items()
                    )
                else:
                    rendered = str(item)
                lines.append(f"{label}: {rendered}")
            return "\n".join(lines)
        if isinstance(value, list):
            return "\n".join(f"- {TravelAIService._stringify_ai_value(item)}" for item in value)
        return str(value)

    @staticmethod
    def _normalize_packing_list(generated: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
        raw_list = generated.get("packing_list", fallback["packing_list"])
        if isinstance(raw_list, dict):
            packing_list = [
                {"category": str(category), "items": [str(item) for item in items] if isinstance(items, list) else [str(items)]}
                for category, items in raw_list.items()
            ]
        elif isinstance(raw_list, list):
            packing_list = []
            for index, item in enumerate(raw_list, start=1):
                if isinstance(item, dict):
                    items = item.get("items", [])
                    packing_list.append(
                        {
                            "category": str(item.get("category") or f"Group {index}"),
                            "items": [str(entry) for entry in items] if isinstance(items, list) else [str(items)],
                        }
                    )
                else:
                    packing_list.append({"category": "General", "items": [str(item)]})
        else:
            packing_list = fallback["packing_list"]

        return {"packing_list": packing_list or fallback["packing_list"]}

    @staticmethod
    def _money(value: Decimal) -> str:
        return f"${value.quantize(Decimal('0.01'))}"
