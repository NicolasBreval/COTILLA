import asyncio
import aiocoap

async def main():
    protocol = await aiocoap.Context.create_client_context()

    request = aiocoap.Message(code=aiocoap.GET, uri='coap://0.0.0.0:5683/00001', payload=b'TEST MESSAGE', mtype=aiocoap.NON)

    await protocol.request(request).response

asyncio.run(main())