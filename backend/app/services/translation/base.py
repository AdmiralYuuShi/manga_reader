from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class TranslationItem:
    translated_text: str | None = None
    error_code: str | None = None


class Translator(Protocol):
    def translate(self, text: str, source_language: str, target_language: str) -> str: ...

    def translate_batch(
        self, texts: list[str], source_language: str, target_language: str
    ) -> list[TranslationItem]: ...
