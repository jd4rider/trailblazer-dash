/*
 * Browser smoke test for the exported Web build.
 *
 *   python3 -m http.server 4173 --directory web/play &
 *   node Tools/smoke.mjs http://127.0.0.1:4173/
 *
 * Boots the Godot build in a portrait viewport, records console errors, taps the
 * screen and writes screenshots to /tmp so the layout can be eyeballed.
 */
import { createRequire } from 'node:module'
import { mkdirSync } from 'node:fs'

const require = createRequire(import.meta.url)
const { chromium } = require('../../starfall-squadron/node_modules/playwright')

const url = process.argv[2] || 'http://127.0.0.1:4173/'
const configs = [
  { name: 'phone', width: 390, height: 844 },
  { name: 'small', width: 360, height: 800 },
  // The arcade wraps the game in a header and footer, leaving about 740px.
  { name: 'arcade-frame', width: 390, height: 740 },
]

const failures = []
const errors = []

mkdirSync('/tmp/tb-shots', { recursive: true })

const browser = await chromium.launch()
for (const config of configs) {
  const context = await browser.newContext({
    viewport: { width: config.width, height: config.height },
    deviceScaleFactor: 2,
    hasTouch: true,
    isMobile: true,
  })
  const page = await context.newPage()
  page.on('pageerror', (error) => errors.push(`${config.name}: ${error.message}`))
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(`${config.name} console: ${message.text()}`)
  })

  await page.goto(url, { waitUntil: 'domcontentloaded' })
  await page.waitForSelector('#canvas', { timeout: 30000 })
  await page.waitForTimeout(9000)

  const state = await page.evaluate(() => {
    const canvas = document.querySelector('#canvas')
    const rect = canvas ? canvas.getBoundingClientRect() : null
    return {
      canvas: rect ? { w: Math.round(rect.width), h: Math.round(rect.height), top: Math.round(rect.top) } : null,
      window: { w: innerWidth, h: innerHeight },
      bridge: typeof window.TrailblazerArcade === 'object',
      bridgeVersion: window.TrailblazerArcade ? window.TrailblazerArcade.version : null,
      status: (document.querySelector('#status') || {}).textContent || '',
      statusVisible: !!document.querySelector('#status') && getComputedStyle(document.querySelector('#status')).display !== 'none',
    }
  })
  if (!state.canvas) failures.push(`${config.name}: no canvas`)
  if (!state.bridge) failures.push(`${config.name}: arcade bridge missing`)
  if (state.canvas && state.canvas.h < state.window.h * 0.9) {
    failures.push(`${config.name}: canvas is ${state.canvas.h}px tall inside a ${state.window.h}px window`)
  }	await page.screenshot({ path: `/tmp/tb-shots/${config.name}-1-boot.png` })
	// CONTINUE is the first row of the bottom stack.
	await page.touchscreen.tap(config.width / 2, config.height * 0.755)
	await page.waitForTimeout(2500)
	await page.screenshot({ path: `/tmp/tb-shots/${config.name}-2-run-ready.png` })
	// START RUNNING sits inside the ready card, below the control hints.
	await page.touchscreen.tap(config.width / 2, config.height * 0.57)
	await page.waitForTimeout(3500)
	await page.screenshot({ path: `/tmp/tb-shots/${config.name}-3-running.png` })
	await page.keyboard.press('ArrowLeft')
	await page.waitForTimeout(600)
	await page.keyboard.press('ArrowUp')
	await page.waitForTimeout(2500)
	await page.screenshot({ path: `/tmp/tb-shots/${config.name}-4-later.png` })

	// Real finger swipes through CDP: Godot's web export listens for touch, and
	// emulated mouse drags alone would not catch a touch-only regression.
	const cdp = await context.newCDPSession(page)
	const swipe = async ([x0, y0], [x1, y1]) => {
		await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: x0, y: y0 }] })
		for (let step = 1; step <= 8; step += 1) {
			await cdp.send('Input.dispatchTouchEvent', {
				type: 'touchMove',
				touchPoints: [{ x: x0 + ((x1 - x0) * step) / 8, y: y0 + ((y1 - y0) * step) / 8 }],
			})
			await page.waitForTimeout(16)
		}
		await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
	}
	const beforeSwipe = await page.screenshot({ path: `/tmp/tb-shots/${config.name}-5-before-swipe.png` })
	await swipe([config.width * 0.5, config.height * 0.74], [config.width * 0.18, config.height * 0.74])
	await page.waitForTimeout(420)
	const afterSwipe = await page.screenshot({ path: `/tmp/tb-shots/${config.name}-6-after-left-swipe.png` })
	if (Buffer.compare(beforeSwipe, afterSwipe) === 0) failures.push(`${config.name}: left swipe changed nothing on screen`)
	await swipe([config.width * 0.5, config.height * 0.72], [config.width * 0.5, config.height * 0.4])
	await page.waitForTimeout(260)
	await page.screenshot({ path: `/tmp/tb-shots/${config.name}-7-after-up-swipe.png` })
	await page.waitForTimeout(2200)
	await page.screenshot({ path: `/tmp/tb-shots/${config.name}-8-swiped.png` })
	// Two frames a second apart: the trail must visibly move, not sit still.
	const before = await page.screenshot()
	await page.waitForTimeout(1100)
	const after = await page.screenshot()
	if (Buffer.compare(before, after) === 0) failures.push(`${config.name}: the run frame is completely static`)

  console.log(config.name, JSON.stringify(state))
  await context.close()
}
await browser.close()

if (errors.length) console.log('page errors:\n' + errors.slice(0, 12).join('\n'))
// Godot prints script failures to the browser console; those are real defects,
// so the build fails rather than only logging them.
for (const message of errors) {
  if (/SCRIPT ERROR|Parse Error|not found in base|Cannot get property/.test(message)) {
    failures.push('script failure: ' + message)
  }
}
if (failures.length) {
  console.log('FAIL\n' + failures.join('\n'))
  process.exit(1)
}
console.log('smoke passed')
