#!/usr/bin/env python3
"""App Store screenshots (iPhone 6.9", 1290x2796) of the live menu, framed like the app (tab bar at the bottom)."""
import asyncio, os
from playwright.async_api import async_playwright

SITE = "https://spesmuz.github.io/uno-menu/"
OUT = os.path.join(os.path.dirname(__file__), "shots", "main")
LABELS = {"ru": ["Меню", "Бронь", "UNO", "Профиль"], "en": ["Menu", "Book", "UNO", "Profile"]}

ICONS = [  # fork.knife, calendar.badge.plus, airplane, person.crop.circle (simple outlines)
    '<path d="M7 2v8a2 2 0 0 0 2 2v10M5 2v6M9 2v6M17 2c-2 1-3 4-3 7h3v13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
    '<rect x="3" y="5" width="16" height="15" rx="3" fill="none" stroke="currentColor" stroke-width="2"/><path d="M3 10h16M8 3v4M14 3v4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="19" cy="18" r="4.5" fill="currentColor"/><path d="M19 16v4M17 18h4" stroke="#0b1430" stroke-width="1.6" stroke-linecap="round"/>',
    '<path d="M2 13l8-1.5L14 4h2l-2 7.5 5-1 2-2.5h1.5l-1 4 1 4H21l-2-2.5-5-1 2 7.5h-2l-4-7.5L2 13z" fill="currentColor"/>',
    '<circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="10" r="3.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M5.5 18.5c1.6-2.4 3.9-3.5 6.5-3.5s4.9 1.1 6.5 3.5" fill="none" stroke="currentColor" stroke-width="2"/>',
]


def bar_html(lang, active=0):
    items = ""
    for i, (lab, ic) in enumerate(zip(LABELS[lang], ICONS)):
        on = i == active
        items += (f'<div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;height:52px;border-radius:26px;'
                  f'{"background:rgba(255,255,255,.13);color:#E8B04B" if on else "color:rgba(255,255,255,.8)"}">'
                  f'<svg width="22" height="22" viewBox="0 0 24 24">{ic}</svg><span style="font:600 11px -apple-system,system-ui,sans-serif">{lab}</span></div>')
    return ('<div id="fakeBar" style="position:fixed;left:14px;right:14px;bottom:22px;height:62px;z-index:99999;display:flex;gap:2px;padding:5px;'
            'border-radius:31px;background:rgba(40,44,60,.72);-webkit-backdrop-filter:blur(20px) saturate(160%);backdrop-filter:blur(20px) saturate(160%);'
            'border:1px solid rgba(255,255,255,.18);box-shadow:0 6px 14px rgba(0,0,0,.35)">' + items + '</div>')


async def main(lang="ru"):
    os.makedirs(OUT, exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch()
        ctx = await b.new_context(viewport={"width": 430, "height": 932}, device_scale_factor=3, is_mobile=True, has_touch=True,
                                  user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 UNOAirwaysApp/1.2.2")
        await ctx.add_init_script(
            "window.UNO_INSETS={t:0,b:90,l:0,r:0,island:{x:152,y:11.3,w:126,h:37.4}};"
            f"try{{localStorage.setItem('uno_lang','{lang}');localStorage.setItem('uno_profile',JSON.stringify({{name:'Aziza Karimova',phone:'+998 90 123 45 67'}}));}}catch(e){{}}")
        pg = await ctx.new_page()
        await pg.goto(SITE + "#menyu", wait_until="networkidle")
        await pg.wait_for_timeout(6000)

        async def frame(name, active=0):
            await pg.evaluate("(h)=>{var o=document.getElementById('fakeBar'); if(o) o.remove(); document.body.insertAdjacentHTML('beforeend', h);}", bar_html(lang, active))
            await pg.wait_for_timeout(600)
            await pg.screenshot(path=os.path.join(OUT, name))
            print("shot", name, flush=True)

        # 1. the menu, on a dish that has a photo
        for _ in range(12):
            has = await pg.evaluate("!!document.querySelector('.slide.center .media img.thumb')")
            if has: break
            await pg.click("#nextBtn"); await pg.wait_for_timeout(900)
        await pg.wait_for_timeout(2500)
        await frame("1.png")
        # 2. the dish card opened (photo/video, description, reviews)
        try:
            await pg.click(".slide.center [data-more]"); await pg.wait_for_timeout(2500)
            await frame("2.png")
            await pg.keyboard.press("Escape"); await pg.wait_for_timeout(500)
            cl = pg.locator(".d-close");
            if await cl.count(): await cl.first.click()
            await pg.wait_for_timeout(800)
        except Exception as e:
            print("detail:", e)
        # 3. another category whose first dish has a photo
        try:
            tabs = pg.locator("#tabs .tab"); n = await tabs.count()
            for i in range(1, n):
                await tabs.nth(i).click(); await pg.wait_for_timeout(1800)
                if await pg.evaluate("!!document.querySelector('.slide.center .media img.thumb')"):
                    await pg.wait_for_timeout(1500); await frame("3.png"); break
            await tabs.nth(0).click(); await pg.wait_for_timeout(1500)
        except Exception as e:
            print("tab:", e)
        # 4. cart and delivery
        try:
            await pg.locator(".slide.center .add-btn").first.click(); await pg.wait_for_timeout(400)
            await pg.locator(".slide.center [data-act=inc]").first.click(); await pg.wait_for_timeout(400)
            await pg.click("#cartBtn"); await pg.wait_for_timeout(1200)
            await frame("4.png")
            d = pg.locator("[data-c=dlv]")
            if await d.count():
                await d.first.click(); await pg.wait_for_timeout(1000)
                a = pg.locator("#dlvAddr")
                if await a.count(): await a.fill("Фергана, ул. Мустакиллик, 12")
                await frame("5.png")
        except Exception as e:
            print("cart:", e)
        await b.close()


if __name__ == "__main__":
    asyncio.run(main())
