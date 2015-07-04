package actions

import (
	"fmt"
	"os"
	"path"
	"strings"
	"testing"

	"github.com/eris-ltd/eris-cli/util"
)

var erisDir string = path.Join(os.TempDir(), "eris")
var actionName string = "do not use"
var oldName string = "wanna do some testing"
var newName string = "yeah lets test shit"
var hash string

func TestMain(m *testing.M) {
	logger.Level = 0
	// logger.Level = 1
	// logger.Level = 2

	if err := testsInit(); err != nil {
		logger.Errorln(err)
		os.Exit(1)
	}

	exitCode := m.Run()

	if os.Getenv("TEST_IN_CIRCLE") != "true" {
		if err := testsTearDown(); err != nil {
			logger.Errorln(err)
			os.Exit(1)
		}
	}

	os.Exit(exitCode)
}

func TestListActionsRaw(t *testing.T) {
	k := ListKnownRaw()

	if len(k) != 1 {
		logger.Errorf("The wrong number of action definitions have been found. Something is wrong.\n")
		t.Fail()
		testsTearDown()
		os.Exit(1)
	}

	if k[0] != "do_not_use" {
		logger.Errorf("Could not find \"do not use\" action definition.\n")
		t.Fail()
		testsTearDown()
		os.Exit(1)
	}
}

func TestLoadActionDefinition(t *testing.T) {
	var e error
	action := strings.Split(actionName, " ")
	act, _, e := LoadActionDefinition(action)
	if e != nil {
		logger.Errorln(e)
		t.FailNow()
	}

	if act.Name != actionName {
		logger.Errorf("FAILURE: improper action name on LOAD. expected: %s\tgot: %s\n", actionName, act.Name)
		t.Fail()
	}
}

func TestDoActionRaw(t *testing.T) {
	act := strings.Split(actionName, " ")
	action, actionVars, err := LoadActionDefinition(act)
	if err != nil {
		logger.Errorln(err)
		t.FailNow()
	}

	if err := DoRaw(action, actionVars, true); err != nil {
		logger.Errorln(err)
		t.Fail()
	}
}

func TestNewActionRaw(t *testing.T) {
	act := strings.Fields(oldName)
	if err := NewActionRaw(act); err != nil {
		logger.Errorln(err)
		t.Fail()
	}
	testExist(t, oldName, true)
}

func TestRenameActionRaw(t *testing.T) {
	testExist(t, newName, false)
	testExist(t, oldName, true)

	if err := RenameActionRaw(oldName, newName); err != nil {
		logger.Errorln(err)
		t.Fail()
	}
	testExist(t, newName, true)
	testExist(t, oldName, false)

	if err := RenameActionRaw(newName, oldName); err != nil {
		logger.Errorln(err)
		t.Fail()
	}
	testExist(t, newName, false)
	testExist(t, oldName, true)
}

func TestRemoveActionRaw(t *testing.T) {
	act := strings.Fields(oldName)
	if err := RmActionRaw(act, true); err != nil {
		logger.Errorln(err)
		t.Fail()
	}
	testExist(t, oldName, false)
}

func testsInit() error {
	// common is initialized on import so
	// we have to manually override these
	// variables to ensure that the tests
	// run correctly.
	util.ChangeErisDir(erisDir)

	// this dumps the ipfs service def into the temp dir which
	// has been set as the erisRoot
	if err := util.Initialize(false, false); err != nil {
		return fmt.Errorf("TRAGIC. Could not initialize the eris dir:\n%s\n", err)
	}

	// init dockerClient
	util.DockerConnect(false)

	return nil
}

func testsTearDown() error {
	if e := os.RemoveAll(erisDir); e != nil {
		return e
	}

	return nil
}

func testExist(t *testing.T, actionName string, toExist bool) {
	var exist bool
	for _, r := range ListKnownRaw() {
		r = strings.Replace(r, "_", " ", -1)
		if r == actionName {
			exist = true
		}
	}

	if toExist != exist {
		if toExist {
			logger.Errorf("Could not find an existing instance of %s\n", actionName)
		} else {
			logger.Errorf("Found an existing instance of %s when I shouldn't have\n", actionName)
		}
		t.Fail()
	}
}
