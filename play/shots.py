#!/usr/bin/env python3
"""Google Play phone screenshots (1080x1920, 9:16) of the live site as the Android app shows it (Menyu/Bron/UNO/Profil tabs)."""
import asyncio, os, sys
from playwright.async_api import async_playwright

SITE = os.environ.get("SITE", "https://spesmuz.github.io/uno-menu/")
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "shots")
UA = "Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36"
PROFILE = {"uz": ("Aziza Karimova", "Farg'ona, Mustaqillik ko'chasi, 12"), "ru": ("Азиза Каримова", "Фергана, ул. Мустакиллик, 12")}


async def run(p, lang):
    out = os.path.join(ROOT, lang); os.makedirs(out, exist_ok=True)
    b = await p.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
    ctx = await b.new_context(viewport={"width": 432, "height": 768}, device_scale_factor=2.5, is_mobile=True, has_touch=True,
                              service_workers="block", user_agent=UA, timezone_id="Asia/Tashkent", locale="ru-RU" if lang == "ru" else "uz-UZ")
    name, addr = PROFILE[lang]
    await ctx.add_init_script(
        "window.UnoKiosk={isApp:()=>true,kioskOn:()=>false,mode:()=>'off'};"
        f"try{{localStorage.setItem('uno_lang','{lang}');localStorage.setItem('uno_inst_later',String(Date.now()));"
        f"localStorage.setItem('uno_profile',JSON.stringify({{name:'{name}',phone:'+998 90 123 45 67'}}));}}catch(e){{}}")
    pg = await ctx.new_page()
    await pg.goto(SITE + "#menyu", wait_until="networkidle")
    await pg.wait_for_timeout(7000)
    n = [0]

    async def shot(tag):
        n[0] += 1
        await pg.wait_for_timeout(700)
        f = os.path.join(out, f"{n[0]}-{tag}.png")
        await pg.screenshot(path=f); print("shot", lang, f, flush=True)

    async def tab(i):
        await pg.click(f'#wtabs button[data-t="{i}"]'); await pg.wait_for_timeout(1500)

    # 1. menu on a dish with a photo
    for _ in range(14):
        if await pg.evaluate("!!document.querySelector('.slide.center .media img.thumb')"): break
        await pg.click("#nextBtn"); await pg.wait_for_timeout(900)
    await pg.wait_for_timeout(2500); await shot("menu")
    # 2. dish card
    try:
        await pg.click(".slide.center [data-more]"); await pg.wait_for_timeout(2500); await shot("dish")
        await pg.keyboard.press("Escape"); await pg.wait_for_timeout(500)
        cl = pg.locator(".d-close")
        if await cl.count() and await cl.first.is_visible(): await cl.first.click()
        await pg.wait_for_timeout(800)
    except Exception as e: print("dish:", e)
    # 3. another category
    try:
        tabs = pg.locator("#tabs .tab"); k = await tabs.count()
        for i in range(2, k):
            await tabs.nth(i).click(); await pg.wait_for_timeout(1800)
            if await pg.evaluate("!!document.querySelector('.slide.center .media img.thumb')"):
                await pg.wait_for_timeout(1500); await shot("category"); break
        await tabs.nth(0).click(); await pg.wait_for_timeout(1500)
    except Exception as e: print("category:", e)
    # 4. cart + delivery
    try:
        await pg.locator(".slide.center .add-btn").first.click(); await pg.wait_for_timeout(400)
        await pg.locator(".slide.center [data-act=inc]").first.click(); await pg.wait_for_timeout(400)
        await pg.click("#cartBtn"); await pg.wait_for_timeout(1200)
        d = pg.locator("[data-c=dlv]")
        if await d.count():
            await d.first.click(); await pg.wait_for_timeout(1000)
            a = pg.locator("#dlvAddr")
            if await a.count(): await a.fill(addr)
        await shot("cart")
        await pg.keyboard.press("Escape"); await pg.wait_for_timeout(600)
        for sel in ("#cartClose", ".cart-close", ".sheet .x", "[data-c=close]"):
            l = pg.locator(sel)
            if await l.count() and await l.first.is_visible(): await l.first.click(); break
        await pg.wait_for_timeout(800)
    except Exception as e: print("cart:", e)
    # 5-7. Bron, UNO, Profil tabs
    for i, tag in ((1, "booking"), (2, "about"), (3, "profile")):
        try: await tab(i); await shot(tag)
        except Exception as e: print(tag, e)
    await b.close()


async def main():
    langs = sys.argv[1:] or ["uz", "ru"]
    async with async_playwright() as p:
        for l in langs: await run(p, l)
    import json
    lst = {l: sorted(f for f in os.listdir(os.path.join(ROOT, l)) if f.endswith(".png")) for l in os.listdir(ROOT) if os.path.isdir(os.path.join(ROOT, l))}
    json.dump(lst, open(os.path.join(ROOT, "list.json"), "w"), ensure_ascii=False, indent=1)

asyncio.run(main())
