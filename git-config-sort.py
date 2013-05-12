from collections import OrderedDict
import git

filePath = '/tmp/git.config'
# Could use SubmoduleConfigParser to get fancier
c = git.GitConfigParser(filePath, False)
c.sections()
# http://stackoverflow.com/questions/8031418/how-to-sort-ordereddict-in-ordereddict-python
c._sections = OrderedDict(sorted(c._sections.iteritems(), key=lambda x: x[0]))
c.write()
del c