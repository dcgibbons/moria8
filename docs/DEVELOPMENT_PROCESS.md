# Development Process

## Why Moria8?

I first played [Moria][vms-moria] in 1986 on a [VAX/VMS][vax-vms] system at
my high school with a large computer specialty program. My best friend and I
spent way too many hours exploring this game, both at school using
[VT220][vt220] terminals, but also at home via my
[Commodore 64][commodore-64] computer and a 300-baud dial-up connection. We
even may have checked out paper teletypes from the school once or twice which
made for an entertaining, if very wasteful, experience.

Playing on the Commodore 64 was interesting given the platform's limitations.
With a native 40-column display, the only way to see the full 80-column screen
was using a terminal program (I no longer remember which one) that had [VT52][vt52]
emulation and custom bitmap fonts to achieve an 80-column text display. To
make this work, each character was limited to only 4 pixels of width.
Especially on a TV, but even with a quality monitor, this was usable only for
those with young eyes, and even then just barely.

The C64 also did not have a 10-key numeric keypad, which Moria used as an
8-way directional movement system. We constantly had to remap in our head to
press the right number keys which led to frequent player death by mistake. It
certainly added to the challenge!

Once my best friend got his [Commodore 128][commodore-128] with an 80-column
capable monitor, things got much more interesting playing the game, but also
our lives had moved on a bit.

[Umoria][umoria] entered the scene in the early '90s. While I didn't play
Umoria as much as I did the original VMS version, it became a staple for me to
try out on new systems and builds since then. It's a great piece of software
and runs just about anywhere with a hosted C environment and enough memory, but
that makes it tough on 8-bit systems.

## The Case for 8-Bit Ports

My experience playing VMS Moria on a C64 always left me wishing for a great
port of Moria to that platform. After all, bigger RPGs ([Ultimas][ultima-series]
in particular) have been developed with 8-bit constraints, so surely Moria with
its simpler terminal UI (TUI) could be made to work? And of course, it could
be, but not using the original source as is.

[BASIC][basic] isn't an option for a full port - it is much too slow and the
memory isn't ample enough on most platforms. The Commodore 128 BASIC would
work, but even there the combination of code + data would be difficult to
manage in the available address space without a lot of overlays.

Assembly language is needed, so that requires a full rewrite of the system
anyway. Using a 40-column screen native to the Commodore 64 also requires a
rethink of much of the system, from the TUI itself to how large dungeons are
stored in memory, to entire features, spell lists, monsters, etc. So the
effort becomes an "inspired by Moria" rather than a straightforward porting
effort. This really reflects how most 8-bit ports were done back in the day -
graphics, sounds, and game features were fair game for tradeoffs on every
platform.

These considerations had only been a relatively recent development of my own,
as I hadn't been interested in retro computers at all until 2020. That changed
with the excellent launch of [Nox Archaist][nox-archaist], an Ultima-like CRPG
for the [Apple II][apple-ii] platform. Before I knew it, I acquired an
[Apple IIgs][apple-iigs], and over the course of the subsequent years the retro
collection expanded way beyond what I expected. Playing with the old Commodore
64 and 128 suddenly became interesting again.

And then, a big change happened: the practical application of agentic coding
tools using AI.

## The Case for and Use of AI and Agentic Coding Tools

I've been using [large language models (LLMs)][large-language-models]
professionally since they were first available, but avoided using them for
coding until 2025. Prior to that, I would usually try out the latest frontier
models with a simple prompt (which grew in complexity as the tools got better):
`create a full featured Space Invaders game` on whatever platform I felt like
targeting. At first, it was just for modern web browsers. Later, I tried it to
target the C64 and other 8-bit platforms.

[Space Invaders][space-invaders] seemed like a great test case - it was a very
simple piece of software, with full disassembly available on the Internet. All
of the art assets, both original and artistic follow-ons, were available online
and every model had likely been trained on this data. It should be trivial for
these tools to recreate this game, right? Not at all. I could often get a
playable game after some effort, but I was surprised at how *difficult* it
remained, compared to other success stories I was reading about.

That all changed in late 2025 with the release of new models and tools from
[Anthropic][anthropic], [Google][google-ai], and [OpenAI][openai]. There was
quite a distinct step-function improvement in the models, but also in the
tooling as well. And the human factor improvement was real too: the methods we
use to leverage these tools became better understood and our techniques also
took a step up to the next level of problem difficulty.

At my day job, I wasn't using agentic coding tools to "code for me" but
instead use them as a productivity tool: faster code typers, design peers,
testing, etc. It was real and beneficial, with good quality - very different
from the way most people think of using these tools for "vibe coding" but
instead using them for real engineering productivity.

At the day job, I'm limited on the sets of tools I can use and the types of
problems I can experiment with. I began looking for some side projects to let
me explore these different tools a bit more deeply. That's where Moria came
back into the picture, with a distinct focus on the Commodore 64 platform.

## How I Use AI on Moria8

I made a specific choice early in my brainstorming about this project: I will
avoid *typing* any code. Instead, I will put on my architect, tech lead, and
engineering manager hats (roles I've done many times over my career) and try
and leverage the AI tools as my team. Not autonomous "go build this feature
for me overnight. kthxbye!" usage, but instead as real engineering partners
with an eye towards performant, reliable, and maintainable software. And if
that turned out not to be possible, yet, then at least it was only on a game
and not a "real" project, right?

Over the course of the project I've used the following:

- Anthropic's [Claude][claude] with [Opus 4.5+][claude-opus-4-5] and
    [Sonnet 4.5+][claude-sonnet-4-5]
- Google's [Antigravity][google-antigravity] and [Gemini CLI][gemini-cli],
    with [Gemini 3.0+][gemini-3]
- OpenAI's [Codex][openai-codex] with [GPT-5.2+][gpt-5-2]
- A variety of open-source models using [Ollama][ollama], such as
    [`qwen3-coder-next`][qwen3-coder-next]

Most of the early code development was done with Claude, but at a certain
complexity I found it consistently making poor choices, getting slower, and
making more and more mistakes. I pivoted to a combination of Codex and Gemini
halfway through the effort with much better results, especially when using
Codex as the coding agent, and Gemini as the fast-thinking analysis and review
tool. Said another way, the proof-of-concept was written with Claude, but all
of the productionization and polishing was done with Codex and Gemini.

### Prompts and Techniques

The [AGENTS.md](../AGENTS.md) file will be useful for those looking for an
example of a good agent configuration for this project. These rules have been
changed many times over the course of the project, and some of the historical
files can be found in the docs subdirectory of the project.

Maintaining these metadata files becomes a critical part of the effort as the
project becomes non-trivial. Using the AI tools themselves to help review
these files and improve upon them was something I did after almost every
feature was completed.

One of the most useful prompts I use regularly is asking the agent to
`interview me until you have 95% confidence in the feature` when using the
planning modes of the tools. I find this dramatically improves the quality of
every feature I ask it to plan. If I skip this step, the tools will do what
they can, but just like working with real humans - poor requirements usually
result in terrible output.

For those curious how the project was kicked off and what the resulting plan
was, the original prompt was the [README.md][original-readme].
Iterating on this prompt with Claude resulted in the
[BUILDPLAN.md][original-buildplan] file and it provides a wealth of
information about the project. Much of the initial work was built directly off
of this plan. This particular technique is an extremely powerful way of
leveraging these tools - define a high-level goal, and then use the agents and
your own design knowledge to produce a solid plan for the project.

### Where AI Breaks Down

#### Chasing Tails

A repeated failure mode I would encounter on *all* of the platforms was
amusingly a reflection of one of my own personal failure modes: doggedly
hacking on a problem when I am tired, rather than sleeping on it and
coming back to a problem with fresh perspective. I made this mistake a lot
when I was younger, and luckily the wisdom of experience has taught me the
warning signs to look for.

I would often catch the AI agents falling into this trap. Some sort of failure
would occur - a failed test, or memory exhaustion, etc. - and the agents would
often get "stuck in a loop" repeatedly trying to resolve something
simple. If I was busy on something else and not paying attention, the agents
could frequently spend hours or days on a task that was not useful to spend
any amount of time on. Said another way, a wrong choice was made by the agent,
and it would blindly go down a path that made no sense to go down - and it
would do so without interruption if left alone.

The big lesson for me on this one was to pay attention and not buy into
the autonomous coding agent hype - at least not yet. If you catch an agent
doing something that is taking more time than it should, or asking to rerun
tests over and over and over, something is up. The best course of action is to
stop it, ask what it is trying to do, and then adjust from there. I would
frequently tell it to ask the consultants (sub-agents) on what the best
course of action would be, and that almost always got it back on track.

Besides seeing this behavior with myself, I've seen it a lot with junior
engineers as they work through problems and get stuck. Some are quick to ask
for help, others will try hard and figure something out - no matter what! -
and they can burn tons of time doing so.

#### Platform Nuances

While I have a solid knowledge of the Commodore 64's architecture and
[6502][mos-6502] assembly language, I was much less well-versed on the
Commodore 128 platform.
This resulted in some poor design choices made between me and the AI tools on
memory layouts that burned a lot of time, and tokens, trying to debug. The
80-column [VDC][mos-8563-vdc] chip in the C128 is also rather unique, and I
knew almost nothing about it, resulting in a poor use of time for both me and
the AI agents as we experimented with the chip; some prototyping on my part
early on would have saved a ton of time here.

##### Memory Constraints

The biggest challenge for Moria8 on 8-bit platforms is not CPU performance, it
is memory constraints. Not only total memory availability, but how it is
structured on each platform.

On the C64 in particular, RAM and ROM share overlapping address spaces and a
processor port register, custom to the [6510][mos-6510] variant of the CPU,
selects the different memory map arrangements. Even so, this still limits you
to a maximum
of slightly less than 64KB of RAM - far too small for Moria8. Swapping in code
dynamically from disk using overlays (i.e. different code sections that share
the same address space but only one can be loaded at a time) is the standard
way most software dealt with this limit. Another option is the RAM Expansion
Unit ([REU][commodore-reu]) which uses DMA to transfer between the extra memory
and memory local to the main address space. Moria8 can leverage both.

The C128 has a different memory arrangement technique. It uses memory banks,
which allow for rapid access to different memory segments without disk
swapping or REU DMA transfer. For Moria8, this allows much more of the program
code and data to be kept in memory and banked in as needed.

In any case, the real constraint is that a given piece of code or data has a
limited size. As features are added to the program, these sizes can be
exceeded. In Moria8, we have made heavy use of assertions in
[Kick Assembler][kick-assembler] to fail builds if these happen. But frequently,
the agents would ignore these or change memory layouts without consulting me.
This would usually manifest as a strange run-time bug that I would only catch
in playtesting. Some of these bugs would then require a major memory reworking
of multiple code segments to address.

Thinking back to the '80s, this was a very real problem that programmers had
to deal with constantly on 8-bit systems: what is your memory map, what code
and data lives where, and what is the maximum size of each area. Besides CPU,
this is the primary limitation of these older platforms.

My favorite failure mode of the AI agents with this issue is when they quietly
decide they need to trim space to make code or data fit an existing segment.
They have deleted code for existing features, but the most amazing choice has
been truncating or abbreviating string data. For example, "You have died."
was turned into "yhd" or "dead" multiple times through the course of the
effort.

#### CPU Performance Bottlenecks

The classic limitation of almost any game, and especially in the 8-bit era:
you just don't have enough CPU cycles to be naive about what is happening.
Even for a turn-based terminal UI game like Moria8, certain game operations
are *expensive*. For example, generating a new dungeon level, or casting the
spell to find all doors and traps on a level results in full memory scans for
the size of a dungeon.

Clever computer science comes to the rescue in these moments, and I found that
the AI agents were sometimes great at this, but just as often naive and
incapable of selecting a choice that resulted in good performance. This is
really where an experienced engineer comes into the picture and can set the
stage for the AI agents to implement something useful and performant.

For example, even as of the v1.0.0 release, moving to the left on the C128
version of the game is significantly slower than moving to the right given
the limitations of how we must communicate with the VDC chip. This will take
some clever rethinking of the VDC update logic to resolve.

### Ignored Rules

The [AGENTS.md](../AGENTS.md) and other files often turn into a shopping list
of rules learned by the agents when you correct them (we used a `lessons.md`
file for this, especially with Codex). In reality, these metadata files can
quickly become large and blow out your model's context window size.

In practice, the AI agents selectively follow the rules you've set over time.
I reached the point where I found these rules pointless to have, and instead
pivoted to build and code constraints as much as possible.

## Parting Thoughts

Development of the Commodore 64 and 128 versions of Moria8 was started on
February 8th, 2026 and version 1.0.0 was released on May 5th, 2026.

My own estimate of how much time the AI tooling saved here is double my own
rate of speed, assuming I could work on the effort full-time. I would have
been much faster had it been a C port rather than assembly, so I'm sure
someone with better 6502 assembly experience would have realized slightly
less gains out of the effort.

While I absolutely have loved coding directly over my career, it is even more
fun to build something fast and focus more on the architecture, design, and
features than the tedium of typing in code. What a time to be alive.

*Written by [Chad Gibbons](https://github.com/dcgibbons), May 2026.*

[original-readme]: https://github.com/dcgibbons/moria8/blob/26067eabef4b8bd51be13e606542893077576b5e/README.md
[original-buildplan]: https://github.com/dcgibbons/moria8/blob/26067eabef4b8bd51be13e606542893077576b5e/BUILDPLAN.md
[vms-moria]: https://github.com/dungeons-of-moria/vms-moria
[vax-vms]: https://wiki.vmssoftware.com/OpenVMS
[vt52]: https://en.wikipedia.org/wiki/VT52
[vt220]: https://terminals-wiki.org/wiki/index.php/DEC_VT220
[commodore-64]: https://en.wikipedia.org/wiki/Commodore_64
[commodore-128]: https://en.wikipedia.org/wiki/Commodore_128
[umoria]: https://umoria.org/
[ultima-series]: https://en.wikipedia.org/wiki/Ultima_(series)
[basic]: https://en.wikipedia.org/wiki/BASIC
[nox-archaist]: https://www.6502workshop.com/p/nox-archaist.html
[apple-ii]: https://en.wikipedia.org/wiki/Apple_II
[apple-iigs]: https://en.wikipedia.org/wiki/Apple_IIGS
[large-language-models]: https://www.britannica.com/topic/large-language-model
[space-invaders]: https://spaceinvaders.jp/
[anthropic]: https://www.anthropic.com/
[google-ai]: https://ai.google/
[openai]: https://openai.com/
[claude]: https://www.anthropic.com/claude
[claude-opus-4-5]: https://www.anthropic.com/news/claude-opus-4-5
[claude-sonnet-4-5]: https://www.anthropic.com/news/claude-sonnet-4-5
[google-antigravity]: https://antigravity.google/
[gemini-cli]: https://github.com/google-gemini/gemini-cli
[gemini-3]: https://blog.google/products-and-platforms/products/gemini/gemini-3/
[openai-codex]: https://openai.com/codex/
[gpt-5-2]: https://openai.com/index/introducing-gpt-5-2
[ollama]: https://ollama.com/
[qwen3-coder-next]: https://ollama.com/library/qwen3-coder-next
[mos-6502]: https://en.wikipedia.org/wiki/MOS_Technology_6502
[mos-6510]: https://en.wikipedia.org/wiki/MOS_Technology_6510
[mos-8563-vdc]: https://en.wikipedia.org/wiki/MOS_Technology_8563
[commodore-reu]: https://www.c64-wiki.com/wiki/Commodore_REU
[kick-assembler]: http://theweb.dk/KickAssembler/
