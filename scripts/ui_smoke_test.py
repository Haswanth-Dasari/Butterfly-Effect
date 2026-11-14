"""End-to-end UI smoke test (needs: pip install playwright && playwright install chromium).
Start a server first (npm start, or npm run mock) and pass its URL:  python scripts/ui_smoke_test.py http://localhost:4100
"""
import sys
URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:4100"
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':1440,'height':860})
    errs=[]
    pg.on('console', lambda m: errs.append(m.type+': '+m.text) if m.type in('error','warning') else None)
    pg.on('pageerror', lambda e: errs.append('PAGEERR '+str(e)))
    pg.goto(URL + '/'); pg.evaluate("localStorage.setItem('butterfly.toured','1')")
    pg.click('summary'); pg.fill('#name','Rin'); pg.click('#join-btn'); pg.wait_for_timeout(3500)
    pg.screenshot(path='/tmp/butterfly_ui_1_map.png')
    # steal
    pg.click('.act-card:has-text("Steal")'); pg.wait_for_timeout(300)
    pg.fill('.form input[type=number]','5'); pg.wait_for_timeout(200)
    pg.screenshot(path='/tmp/butterfly_ui_2_form.png')
    pg.click('.form button[type=submit]'); pg.wait_for_timeout(700)
    pg.screenshot(path='/tmp/butterfly_ui_3_ripple.png')
    pg.wait_for_timeout(1800)
    pg.click('.act-card:has-text("Rumor")'); pg.click('.form button[type=submit]'); pg.wait_for_timeout(800)
    # end day
    pg.click('#end-day-top'); pg.wait_for_timeout(7000)
    pg.screenshot(path='/tmp/butterfly_ui_4_bell.png')
    pg.click('.modal .btn.primary'); pg.wait_for_timeout(1200)
    pg.click('.tab[data-tab=why]'); pg.wait_for_timeout(500)
    pg.screenshot(path='/tmp/butterfly_ui_5_feed.png')
    pg.click('.fev.cascade'); pg.wait_for_timeout(2500)
    pg.screenshot(path='/tmp/butterfly_ui_6_chron.png')
    pg.click('.tab[data-tab=time]'); pg.wait_for_timeout(300)
    pg.evaluate("const s=document.querySelector('#p-time input[type=range]'); s.value=0; s.dispatchEvent(new Event('input'))"); pg.wait_for_timeout(1500)
    pg.screenshot(path='/tmp/butterfly_ui_7_time.png')
    pg.click('#p-time button:has-text("Rewind")'); pg.wait_for_timeout(600)
    pg.fill('#p-worlds input[type=text]','What if I never stole'); pg.click('#p-worlds button:has-text("Create")'); pg.wait_for_timeout(3000)
    pg.screenshot(path='/tmp/butterfly_ui_8_worlds.png')
    pg.click('.tab[data-tab=village]'); pg.wait_for_timeout(1200)
    pg.screenshot(path='/tmp/butterfly_ui_9_village.png')
    print('\n'.join(errs[:20]) or 'no console errors')
    b.close()
