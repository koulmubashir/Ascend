b64 = open('assets/bodymap.b64').read().replace('\n','')
tpl = open('mockup-template.html').read()
open('today-screen.html','w').write(tpl.replace('__IMG__', 'data:image/png;base64,' + b64))
print('wrote today-screen.html')
